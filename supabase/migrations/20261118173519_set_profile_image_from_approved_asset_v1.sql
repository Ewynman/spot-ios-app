-- Profile photos must be moderated before they become the caller's avatar.
-- Clients insert a pending profile_image media_assets row, upload to pending_images,
-- and invoke moderate-image. This RPC is the only authenticated write path for
-- users.profile_image_url / profile_image_asset_id: it accepts an approved asset
-- the caller owns and stores a private storage reference (not a public URL).
--
-- approved_profile_images is private. media_assets is FORCE RLS and select-own,
-- so a storage policy subquery cannot see another user's asset. The visibility
-- helper is SECURITY DEFINER with row_security off, matching user_blocks_duplicate_exists.

create or replace function public.profile_image_object_is_current(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.users u
    join public.media_assets ma on ma.id = u.profile_image_asset_id
    where ma.kind = 'profile_image'
      and ma.status = 'approved'
      and ma.approved_bucket = 'approved_profile_images'
      and ma.approved_path = p_object_name
      and ma.owner_id = u.id
  );
$$;

alter function public.profile_image_object_is_current(text) owner to postgres;
revoke all on function public.profile_image_object_is_current(text) from public;
grant execute on function public.profile_image_object_is_current(text) to authenticated;

comment on function public.profile_image_object_is_current(text) is
  'True when the storage object is the current approved profile image of its owner. Used by approved_profile_images SELECT so other signed-in users can load avatars.';

drop policy if exists approved_profile_images_select_current on storage.objects;
create policy approved_profile_images_select_current
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'approved_profile_images'
    and public.profile_image_object_is_current(name)
  );

create or replace function public.set_profile_image_from_approved_asset_v1(p_media_asset_id uuid)
returns text
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  uid uuid := auth.uid();
  v_bucket text;
  v_path text;
  v_ref text;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select ma.approved_bucket, ma.approved_path
    into v_bucket, v_path
  from public.media_assets ma
  where ma.id = p_media_asset_id
    and ma.owner_id = uid
    and ma.kind = 'profile_image'
    and ma.status = 'approved'
    and ma.approved_bucket = 'approved_profile_images'
    and ma.approved_path is not null
    and ma.approved_path <> '';

  if v_bucket is null or v_path is null then
    raise exception 'profile_image_not_approved' using errcode = '42501';
  end if;

  if split_part(v_path, '/', 1) <> lower(uid::text) then
    raise exception 'profile_image_path_mismatch' using errcode = '42501';
  end if;

  v_ref := 'spot-storage://' || v_bucket || '/' || v_path;

  update public.users
  set profile_image_asset_id = p_media_asset_id,
      profile_image_url = v_ref
  where id = uid;

  if not found then
    raise exception 'profile_user_missing' using errcode = 'P0002';
  end if;

  return v_ref;
end;
$$;

alter function public.set_profile_image_from_approved_asset_v1(uuid) owner to postgres;
revoke all on function public.set_profile_image_from_approved_asset_v1(uuid) from public;
grant execute on function public.set_profile_image_from_approved_asset_v1(uuid) to authenticated;

comment on function public.set_profile_image_from_approved_asset_v1(uuid) is
  'Sets the caller avatar from an approved profile_image media asset they own. Writes a spot-storage reference, never a client-supplied URL.';

-- Direct updates of profile_image_url bypass moderation. Keep the other
-- column grants from 20260509120000_users_grants_user_blocks_insert_fix.sql.
revoke update on table public.users from authenticated;
grant update (
  email,
  email_verified,
  username,
  username_lower,
  is_private,
  is_pro,
  pro_until,
  last_active_at,
  locale
) on table public.users to authenticated;
