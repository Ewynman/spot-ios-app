
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
