-- Azure Content Safety image moderation (v1): media_assets, buckets, RLS,
-- publish_spot_with_approved_media_assets_v1, storage policies, legacy backfill.
--
-- NOTE: This file is the source of truth. It was applied to production in parts
-- via Supabase MCP apply_migration (image_moderation_azure_v1_part{1,2,3}).

-- ---------------------------------------------------------------------------
-- 1. Storage buckets (private)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('pending_images', 'pending_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[]),
  ('approved_spot_images', 'approved_spot_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[]),
  ('approved_profile_images', 'approved_profile_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 2. Core tables
-- ---------------------------------------------------------------------------
create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('spot_image', 'profile_image')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'failed', 'deleted', 'legacy_unmoderated')),
  pending_bucket text,
  pending_path text,
  approved_bucket text,
  approved_path text,
  linked_spot_id uuid references public.spots (id) on delete set null,
  mime_type text,
  byte_size integer,
  width integer,
  height integer,
  sha256 text,
  scores jsonb not null default '{}'::jsonb,
  azure_result jsonb,
  rejection_reason text,
  moderation_provider text not null default 'azure_content_safety',
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_assets_pending_path_required check (
    status = 'deleted'
    or pending_path is not null
    or approved_path is not null
  )
);

create unique index if not exists media_assets_approved_location_uniq
  on public.media_assets (approved_bucket, approved_path)
  where approved_path is not null and approved_bucket is not null;

create index if not exists media_assets_owner_status_idx
  on public.media_assets (owner_id, status);

create index if not exists media_assets_kind_status_idx
  on public.media_assets (kind, status);

create index if not exists media_assets_created_at_idx
  on public.media_assets (created_at desc);

create index if not exists media_assets_linked_spot_idx
  on public.media_assets (linked_spot_id)
  where linked_spot_id is not null;

create table if not exists public.media_moderation_events (
  id uuid primary key default gen_random_uuid(),
  media_asset_id uuid not null references public.media_assets (id) on delete cascade,
  actor_user_id uuid references auth.users (id) on delete set null,
  provider text not null default 'azure_content_safety',
  status text not null check (status in ('approved', 'rejected', 'failed')),
  scores jsonb not null default '{}'::jsonb,
  raw_result jsonb,
  reason text,
  error_code text,
  created_at timestamptz not null default now()
);

create index if not exists media_moderation_events_asset_idx
  on public.media_moderation_events (media_asset_id, created_at desc);

alter table public.spot_images
  add column if not exists media_asset_id uuid references public.media_assets (id) on delete set null;

alter table public.spot_images
  add column if not exists storage_bucket text not null default 'spots';

comment on column public.spot_images.storage_bucket is
  'Supabase Storage bucket id for storage_path (default spots; moderated posts use approved_spot_images).';

alter table public.users
  add column if not exists profile_image_asset_id uuid references public.media_assets (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 3. RLS: media_assets (client insert pending / select own only)
-- ---------------------------------------------------------------------------
alter table public.media_assets enable row level security;
alter table public.media_assets force row level security;

revoke all on table public.media_assets from anon;
grant select, insert on table public.media_assets to authenticated;

drop policy if exists media_assets_select_own on public.media_assets;
create policy media_assets_select_own
  on public.media_assets
  for select
  to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists media_assets_insert_own_pending on public.media_assets;
create policy media_assets_insert_own_pending
  on public.media_assets
  for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and status = 'pending'
    and kind in ('spot_image', 'profile_image')
  );

-- ---------------------------------------------------------------------------
-- 4. RLS: media_moderation_events (no client access; service_role bypasses RLS)
-- ---------------------------------------------------------------------------
alter table public.media_moderation_events enable row level security;
alter table public.media_moderation_events force row level security;

revoke all on table public.media_moderation_events from anon;
revoke all on table public.media_moderation_events from authenticated;

-- ---------------------------------------------------------------------------
-- 5. Storage policies: pending_images (owner folder = auth.uid())
-- ---------------------------------------------------------------------------
drop policy if exists pending_images_insert_own_folder on storage.objects;
create policy pending_images_insert_own_folder
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'pending_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists pending_images_select_own_folder on storage.objects;
create policy pending_images_select_own_folder
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'pending_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists pending_images_update_own_folder on storage.objects;
create policy pending_images_update_own_folder
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'pending_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'pending_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists pending_images_delete_own_folder on storage.objects;
create policy pending_images_delete_own_folder
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'pending_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- 6. Storage policies: approved_spot_images (read via visible spot only)
-- ---------------------------------------------------------------------------
drop policy if exists approved_spot_images_select_visible on storage.objects;
create policy approved_spot_images_select_visible
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'approved_spot_images'
    and exists (
      select 1
      from public.spot_images si
      join public.spots s on s.id = si.spot_id
      where si.storage_bucket = 'approved_spot_images'
        and si.storage_path = name
        and public.can_view_spot(s.id)
    )
  );

-- No authenticated INSERT/UPDATE/DELETE on approved buckets (Edge Function uses service role).

-- ---------------------------------------------------------------------------
-- 7. Storage policies: approved_profile_images (owner reads own file)
-- ---------------------------------------------------------------------------
drop policy if exists approved_profile_images_select_own on storage.objects;
create policy approved_profile_images_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'approved_profile_images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- 8. Publish RPC: only approved spot_image assets owned by caller
-- ---------------------------------------------------------------------------
create or replace function public.publish_spot_with_approved_media_assets_v1(
  p_vibe_tag_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_location_name text,
  p_media_asset_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_spot_id uuid;
  v_idx int := 0;
  v_aid uuid;
  v_priv boolean;
  v_buck text;
  v_path text;
  n int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if p_media_asset_ids is null then
    raise exception 'p_media_asset_ids required';
  end if;

  n := coalesce(array_length(p_media_asset_ids, 1), 0);
  if n < 1 or n > 10 then
    raise exception 'between 1 and 10 images required';
  end if;

  if n <> cardinality(array(select distinct unnest(p_media_asset_ids))) then
    raise exception 'duplicate media_asset_ids';
  end if;

  if not exists (select 1 from public.vibe_tags vt where vt.id = p_vibe_tag_id) then
    raise exception 'invalid vibe_tag_id';
  end if;

  foreach v_aid in array p_media_asset_ids
  loop
    if not exists (
      select 1
      from public.media_assets ma
      where ma.id = v_aid
        and ma.owner_id = v_uid
        and ma.kind = 'spot_image'
        and ma.status = 'approved'
        and ma.linked_spot_id is null
        and ma.approved_bucket is not null
        and ma.approved_path is not null
    ) then
      raise exception 'invalid or unavailable media asset %', v_aid;
    end if;
  end loop;

  select coalesce(u.is_private, false) into v_priv
  from public.users u
  where u.id = v_uid;

  insert into public.spots (
    user_id,
    vibe_tag_id,
    caption,
    latitude,
    longitude,
    location_name,
    author_is_private_snapshot
  )
  values (
    v_uid,
    p_vibe_tag_id,
    '',
    p_latitude,
    p_longitude,
    trim(coalesce(p_location_name, '')),
    coalesce(v_priv, false)
  )
  returning id into v_spot_id;

  v_idx := 0;
  foreach v_aid in array p_media_asset_ids
  loop
    select ma.approved_bucket, ma.approved_path
      into v_buck, v_path
    from public.media_assets ma
    where ma.id = v_aid;

    insert into public.spot_images (
      spot_id,
      storage_path,
      public_url,
      sort_index,
      storage_bucket,
      media_asset_id
    )
    values (
      v_spot_id,
      v_path,
      v_path,
      v_idx,
      v_buck,
      v_aid
    );

    update public.media_assets
    set linked_spot_id = v_spot_id,
        updated_at = now()
    where id = v_aid;

    v_idx := v_idx + 1;
  end loop;

  return v_spot_id;
end;
$$;

revoke all on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) from public;
grant execute on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) to authenticated;

comment on function public.publish_spot_with_approved_media_assets_v1 is
  'Creates a spot and spot_images rows only for approved moderated media_assets (server-side gate).';

-- ---------------------------------------------------------------------------
-- 9. Legacy backfill: media_assets for existing spot_images (spots bucket)
-- ---------------------------------------------------------------------------
insert into public.media_assets (
  owner_id,
  kind,
  status,
  approved_bucket,
  approved_path,
  mime_type
)
select s.user_id, 'spot_image', 'legacy_unmoderated', 'spots', si.storage_path, 'image/jpeg'
from public.spot_images si
join public.spots s on s.id = si.spot_id
where si.media_asset_id is null
  and si.storage_path is not null
  and trim(si.storage_path) <> ''
  and not exists (
    select 1
    from public.media_assets ma
    where ma.approved_bucket = 'spots'
      and ma.approved_path = si.storage_path
      and ma.owner_id = s.user_id
      and ma.kind = 'spot_image'
  );

update public.spot_images si
set media_asset_id = ma.id
from public.media_assets ma, public.spots s
where si.spot_id = s.id
  and ma.owner_id = s.user_id
  and ma.approved_bucket = 'spots'
  and ma.approved_path = si.storage_path
  and ma.kind = 'spot_image'
  and ma.status = 'legacy_unmoderated'
  and si.media_asset_id is null;

-- ---------------------------------------------------------------------------
-- 10. delete_my_account: purge media rows before spots
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  perform set_config('lock_timeout', '5s', true);

  delete from public.user_feed_events where user_id = uid;
  delete from public.feed_impressions
  where user_id = uid
     or spot_id in (select id from public.spots where user_id = uid);
  delete from public.user_vibe_affinities where user_id = uid;
  delete from public.user_creator_affinities where user_id = uid;
  delete from public.user_feed_profiles where user_id = uid;
  delete from public.user_hidden_spots where user_id = uid;

  delete from public.follows where follower_id = uid or followee_id = uid;
  delete from public.follow_requests where requester_id = uid or target_user_id = uid;
  delete from public.user_blocks where blocker_id = uid or blocked_user_id = uid;

  delete from public.spot_likes where user_id = uid;
  delete from public.spot_bookmarks where user_id = uid;

  if to_regclass('public.reports') is not null then
    execute '
      delete from public.reports
      where reporter_id = $1
         or owner_id = $1
         or spot_id in (select id from public.spots where user_id = $1)
    ' using uid;
  end if;

  delete from public.bookmark_collection_spots
  where collection_id in (select id from public.bookmark_collections where user_id = uid);
  delete from public.bookmark_collections where user_id = uid;

  delete from public.spot_likes where spot_id in (select id from public.spots where user_id = uid);
  delete from public.spot_bookmarks where spot_id in (select id from public.spots where user_id = uid);
  delete from public.feed_impressions where spot_id in (select id from public.spots where user_id = uid);
  delete from public.user_feed_events where spot_id in (select id from public.spots where user_id = uid);

  update public.spot_images si
  set media_asset_id = null
  from public.spots s
  where si.spot_id = s.id
    and s.user_id = uid;

  update public.users
  set profile_image_asset_id = null
  where id = uid;

  delete from public.media_assets where owner_id = uid;

  delete from public.spot_images where spot_id in (select id from public.spots where user_id = uid);
  delete from public.spots where user_id = uid;

  delete from public.users where id = uid;

  delete from auth.refresh_tokens
  where user_id = uid::text
     or session_id in (select id from auth.sessions where user_id = uid);
  delete from auth.sessions where user_id = uid;
  delete from auth.identities where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Deletes the authenticated user''s app data and auth user. Purges media_assets. Storage blobs are purged separately by the client.';
