-- Spot production security sweep (Part 1): least privilege, RLS, storage, helpers.
-- Replaces permissive dev_authenticated_all policies with relationship-aware rules.
-- See SecurityAuditReport.md for inventory and rationale.

-- ---------------------------------------------------------------------------
-- 0. Default privileges (deny-by-default for objects created by postgres)
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- 1. Helper functions (SECURITY DEFINER + fixed search_path)
-- ---------------------------------------------------------------------------
create or replace function public.user_has_block_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = p_a and ub.blocked_user_id = p_b)
       or (ub.blocker_id = p_b and ub.blocked_user_id = p_a)
  );
$$;

create or replace function public.is_spot_owner(p_spot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.spots s
    where s.id = p_spot_id
      and s.user_id = (select auth.uid())
  );
$$;

create or replace function public.can_view_author(p_author uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_author = (select auth.uid())
    or (
      not public.user_has_block_between((select auth.uid()), p_author)
      and (
        exists (
          select 1
          from public.users u
          where u.id = p_author
            and coalesce(u.is_private, false) = false
        )
        or exists (
          select 1
          from public.follows f
          where f.follower_id = (select auth.uid())
            and f.followee_id = p_author
        )
      )
    );
$$;

create or replace function public.can_view_spot(p_spot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.spots s
    where s.id = p_spot_id
      and public.can_view_author(s.user_id)
  );
$$;

revoke all on function public.user_has_block_between(uuid, uuid) from public;
revoke all on function public.is_spot_owner(uuid) from public;
revoke all on function public.can_view_author(uuid) from public;
revoke all on function public.can_view_spot(uuid) from public;
grant execute on function public.user_has_block_between(uuid, uuid) to authenticated;
grant execute on function public.is_spot_owner(uuid) to authenticated;
grant execute on function public.can_view_author(uuid) to authenticated;
grant execute on function public.can_view_spot(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Reports table (app inserts; no client reads)
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  spot_id uuid not null references public.spots (id) on delete cascade,
  reporter_id uuid not null references public.users (id),
  owner_id uuid not null references public.users (id),
  reason text not null,
  details text not null default '',
  platform text not null,
  app_version text not null
);

alter table public.reports enable row level security;
alter table public.reports force row level security;

drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own
  on public.reports
  for insert
  to authenticated
  with check (reporter_id = (select auth.uid()));

revoke all on table public.reports from anon;
revoke all on table public.reports from authenticated;
grant insert on table public.reports to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Safe profile projection (no email); SECURITY DEFINER owner read + WHERE
-- ---------------------------------------------------------------------------
create or replace view public.users_public as
select
  u.id,
  u.username,
  u.username_lower,
  u.profile_image_url,
  u.is_private,
  u.is_pro,
  u.pro_until,
  u.spots_count,
  u.created_at,
  u.updated_at
from public.users u
where (select auth.uid()) is not null
  and (
    u.id = (select auth.uid())
    or (
      not public.user_has_block_between((select auth.uid()), u.id)
      and (
        not coalesce(u.is_private, false)
        or exists (
          select 1
          from public.follows f
          where f.follower_id = (select auth.uid())
            and f.followee_id = u.id
        )
      )
    )
  );

alter view public.users_public owner to postgres;
alter view public.users_public set (security_invoker = false);

grant select on public.users_public to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Drop legacy permissive policies
-- ---------------------------------------------------------------------------
drop policy if exists dev_authenticated_all on public.users;
drop policy if exists dev_authenticated_all on public.spots;
drop policy if exists dev_authenticated_all on public.spot_images;
drop policy if exists dev_authenticated_all on public.spot_likes;
drop policy if exists dev_authenticated_all on public.spot_bookmarks;
drop policy if exists dev_authenticated_all on public.follows;
drop policy if exists dev_authenticated_all on public.follow_requests;
drop policy if exists dev_authenticated_all on public.user_blocks;
drop policy if exists dev_authenticated_all on public.bookmark_collections;
drop policy if exists dev_authenticated_all on public.bookmark_collection_spots;
drop policy if exists dev_authenticated_all on public.vibe_tags;

drop policy if exists dev_avatars_authenticated_all on storage.objects;
drop policy if exists spots_insert_own_folder on storage.objects;
drop policy if exists spots_select_own_folder on storage.objects;
drop policy if exists spots_update_own_folder on storage.objects;

-- ---------------------------------------------------------------------------
-- 5. public.users — own row only at table level (others use users_public)
-- ---------------------------------------------------------------------------
create policy users_select_own
  on public.users
  for select
  to authenticated
  using (id = (select auth.uid()));

create policy users_insert_own
  on public.users
  for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy users_update_own
  on public.users
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy users_delete_own
  on public.users
  for delete
  to authenticated
  using (id = (select auth.uid()));

-- Server-owned counters / entitlements: narrow UPDATE columns
revoke update on table public.users from authenticated;
-- is_pro / pro_until: still writable by the app today (StoreKit / deep link).
-- Follow-up: move entitlement writes to a server-only webhook or RPC.
grant update (
  email,
  email_verified,
  username,
  username_lower,
  profile_image_url,
  is_private,
  is_pro,
  pro_until,
  last_active_at,
  locale
) on table public.users to authenticated;

alter table public.users force row level security;

-- ---------------------------------------------------------------------------
-- 6. Spots
-- ---------------------------------------------------------------------------
create policy spots_select_visible
  on public.spots
  for select
  to authenticated
  using (public.can_view_spot(id));

create policy spots_insert_own
  on public.spots
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy spots_update_own
  on public.spots
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy spots_delete_own
  on public.spots
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

revoke update on table public.spots from authenticated;
grant update (
  vibe_tag_id,
  caption,
  latitude,
  longitude,
  location_name,
  author_is_private_snapshot
) on table public.spots to authenticated;

alter table public.spots force row level security;

-- ---------------------------------------------------------------------------
-- 7. Spot images
-- ---------------------------------------------------------------------------
create policy spot_images_select_visible
  on public.spot_images
  for select
  to authenticated
  using (public.can_view_spot(spot_id));

create policy spot_images_insert_own_spot
  on public.spot_images
  for insert
  to authenticated
  with check (public.is_spot_owner(spot_id));

create policy spot_images_update_own_spot
  on public.spot_images
  for update
  to authenticated
  using (public.is_spot_owner(spot_id))
  with check (public.is_spot_owner(spot_id));

create policy spot_images_delete_own_spot
  on public.spot_images
  for delete
  to authenticated
  using (public.is_spot_owner(spot_id));

alter table public.spot_images force row level security;

-- ---------------------------------------------------------------------------
-- 8. Likes / bookmarks
-- ---------------------------------------------------------------------------
create policy spot_likes_select_own
  on public.spot_likes
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy spot_likes_insert_own_visible
  on public.spot_likes
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.can_view_spot(spot_id)
  );

create policy spot_likes_delete_own
  on public.spot_likes
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.spot_likes force row level security;

create policy spot_bookmarks_select_own
  on public.spot_bookmarks
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy spot_bookmarks_insert_own_visible
  on public.spot_bookmarks
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.can_view_spot(spot_id)
  );

create policy spot_bookmarks_delete_own
  on public.spot_bookmarks
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.spot_bookmarks force row level security;

-- ---------------------------------------------------------------------------
-- 9. Follow graph
-- ---------------------------------------------------------------------------
create policy follows_select_related
  on public.follows
  for select
  to authenticated
  using (
    follower_id = (select auth.uid())
    or followee_id = (select auth.uid())
  );

create policy follows_insert_self
  on public.follows
  for insert
  to authenticated
  with check (
    follower_id = (select auth.uid())
    and follower_id <> followee_id
    and not public.user_has_block_between(follower_id, followee_id)
  );

create policy follows_delete_related
  on public.follows
  for delete
  to authenticated
  using (
    follower_id = (select auth.uid())
    or followee_id = (select auth.uid())
  );

alter table public.follows force row level security;

create policy follow_requests_select_related
  on public.follow_requests
  for select
  to authenticated
  using (
    requester_id = (select auth.uid())
    or target_user_id = (select auth.uid())
  );

create policy follow_requests_insert_self
  on public.follow_requests
  for insert
  to authenticated
  with check (
    requester_id = (select auth.uid())
    and requester_id <> target_user_id
    and not public.user_has_block_between(requester_id, target_user_id)
  );

create policy follow_requests_update_parties
  on public.follow_requests
  for update
  to authenticated
  using (
    requester_id = (select auth.uid())
    or target_user_id = (select auth.uid())
  )
  with check (
    requester_id = (select auth.uid())
    or target_user_id = (select auth.uid())
  );

create policy follow_requests_delete_parties
  on public.follow_requests
  for delete
  to authenticated
  using (
    requester_id = (select auth.uid())
    or target_user_id = (select auth.uid())
  );

alter table public.follow_requests force row level security;

-- ---------------------------------------------------------------------------
-- 10. Blocks
-- ---------------------------------------------------------------------------
create policy user_blocks_select_own
  on public.user_blocks
  for select
  to authenticated
  using (blocker_id = (select auth.uid()));

create policy user_blocks_insert_own
  on public.user_blocks
  for insert
  to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocker_id <> blocked_user_id
    and not public.user_has_block_between(blocker_id, blocked_user_id)
  );

create policy user_blocks_delete_own
  on public.user_blocks
  for delete
  to authenticated
  using (blocker_id = (select auth.uid()));

alter table public.user_blocks force row level security;

-- ---------------------------------------------------------------------------
-- 11. Bookmark collections
-- ---------------------------------------------------------------------------
create policy bookmark_collections_select_own
  on public.bookmark_collections
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy bookmark_collections_insert_own
  on public.bookmark_collections
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy bookmark_collections_update_own
  on public.bookmark_collections
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy bookmark_collections_delete_own
  on public.bookmark_collections
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.bookmark_collections force row level security;

create policy bcs_select_own_collection
  on public.bookmark_collection_spots
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookmark_collections bc
      where bc.id = collection_id
        and bc.user_id = (select auth.uid())
    )
  );

create policy bcs_insert_own_visible
  on public.bookmark_collection_spots
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.bookmark_collections bc
      where bc.id = collection_id
        and bc.user_id = (select auth.uid())
    )
    and public.can_view_spot(spot_id)
  );

create policy bcs_update_own_collection
  on public.bookmark_collection_spots
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.bookmark_collections bc
      where bc.id = collection_id
        and bc.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.bookmark_collections bc
      where bc.id = collection_id
        and bc.user_id = (select auth.uid())
    )
  );

create policy bcs_delete_own_collection
  on public.bookmark_collection_spots
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.bookmark_collections bc
      where bc.id = collection_id
        and bc.user_id = (select auth.uid())
    )
  );

alter table public.bookmark_collection_spots force row level security;

-- ---------------------------------------------------------------------------
-- 12. Vibe tags (catalog: read all, insert new; no client updates)
-- ---------------------------------------------------------------------------
create policy vibe_tags_select_all
  on public.vibe_tags
  for select
  to authenticated
  using (true);

create policy vibe_tags_insert_authenticated
  on public.vibe_tags
  for insert
  to authenticated
  with check (true);

alter table public.vibe_tags force row level security;

revoke delete, update on table public.vibe_tags from authenticated;

-- ---------------------------------------------------------------------------
-- 13. Feed / personalization (owner-scoped; tighten role to authenticated)
-- ---------------------------------------------------------------------------
drop policy if exists "feed impressions are insertable by owner" on public.feed_impressions;
drop policy if exists "feed impressions are readable by owner" on public.feed_impressions;
drop policy if exists "feed impressions are updatable by owner" on public.feed_impressions;

create policy feed_impressions_select_own
  on public.feed_impressions
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy feed_impressions_insert_own
  on public.feed_impressions
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy feed_impressions_update_own
  on public.feed_impressions
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

alter table public.feed_impressions force row level security;

drop policy if exists "feed events insertable by owner" on public.user_feed_events;
drop policy if exists "feed events readable by owner" on public.user_feed_events;

create policy user_feed_events_select_own
  on public.user_feed_events
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy user_feed_events_insert_own
  on public.user_feed_events
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

alter table public.user_feed_events force row level security;

drop policy if exists "hidden spots insertable by owner" on public.user_hidden_spots;
drop policy if exists "hidden spots readable by owner" on public.user_hidden_spots;
drop policy if exists "hidden spots updatable by owner" on public.user_hidden_spots;

create policy user_hidden_spots_select_own
  on public.user_hidden_spots
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy user_hidden_spots_insert_own
  on public.user_hidden_spots
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy user_hidden_spots_update_own
  on public.user_hidden_spots
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy user_hidden_spots_delete_own
  on public.user_hidden_spots
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.user_hidden_spots force row level security;

drop policy if exists "vibe affinities readable by owner" on public.user_vibe_affinities;
create policy user_vibe_affinities_select_own
  on public.user_vibe_affinities
  for select
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.user_vibe_affinities force row level security;
revoke insert, update, delete on table public.user_vibe_affinities from authenticated;

drop policy if exists "creator affinities readable by owner" on public.user_creator_affinities;
create policy user_creator_affinities_select_own
  on public.user_creator_affinities
  for select
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.user_creator_affinities force row level security;
revoke insert, update, delete on table public.user_creator_affinities from authenticated;

drop policy if exists user_feed_profiles_owner_select on public.user_feed_profiles;
create policy user_feed_profiles_select_own
  on public.user_feed_profiles
  for select
  to authenticated
  using (user_id = (select auth.uid()));

alter table public.user_feed_profiles force row level security;
revoke insert, update, delete on table public.user_feed_profiles from authenticated;

-- ---------------------------------------------------------------------------
-- 14. Aggregate health / support (no client reads)
-- ---------------------------------------------------------------------------
-- feed_v2_health is a materialized summary object (may be a view); do not ALTER TABLE RLS on it.
revoke select, insert, update, delete on table public.feed_v2_health from anon;
revoke select, insert, update, delete on table public.feed_v2_health from authenticated;

-- support_requests: keep server-only reads; allow authenticated inserts for in-app support if added later
revoke select on table public.support_requests from authenticated;
revoke select on table public.support_requests from anon;

-- ---------------------------------------------------------------------------
-- 15. Revoke anon direct DML on app tables
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------------------
-- 16. Storage (avatars + spots)
-- ---------------------------------------------------------------------------
create policy avatars_insert_own_folder
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_select_own_folder
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_update_own_folder
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_delete_own_folder
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy spots_storage_insert_own_prefix
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'spots'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy spots_storage_update_own_prefix
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'spots'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'spots'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy spots_storage_delete_own_prefix
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'spots'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Read spot media for any object path tied to a visible spot (feed signing).
create policy spots_storage_select_visible
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'spots'
    and exists (
      select 1
      from public.spot_images si
      join public.spots s on s.id = si.spot_id
      where si.storage_path = name
        and public.can_view_spot(s.id)
    )
  );

-- ---------------------------------------------------------------------------
-- 17. Indexes for policy predicates
-- ---------------------------------------------------------------------------
create index if not exists idx_spots_user_id on public.spots (user_id);
create index if not exists idx_spot_images_spot_id on public.spot_images (spot_id);
create index if not exists idx_spot_likes_user_id on public.spot_likes (user_id);
create index if not exists idx_spot_likes_spot_id on public.spot_likes (spot_id);
create index if not exists idx_spot_bookmarks_user_id on public.spot_bookmarks (user_id);
create index if not exists idx_spot_bookmarks_spot_id on public.spot_bookmarks (spot_id);
create index if not exists idx_follows_follower_followee on public.follows (follower_id, followee_id);
create index if not exists idx_follows_followee_follower on public.follows (followee_id, follower_id);
create index if not exists idx_follow_requests_requester on public.follow_requests (requester_id);
create index if not exists idx_follow_requests_target on public.follow_requests (target_user_id);
create index if not exists idx_user_blocks_blocker_blocked on public.user_blocks (blocker_id, blocked_user_id);
create index if not exists idx_user_blocks_blocked_blocker on public.user_blocks (blocked_user_id, blocker_id);
create index if not exists idx_bookmark_collections_user_id on public.bookmark_collections (user_id);
create index if not exists idx_bookmark_collection_spots_collection on public.bookmark_collection_spots (collection_id);
create index if not exists idx_bookmark_collection_spots_spot on public.bookmark_collection_spots (spot_id);
create index if not exists idx_feed_impressions_user on public.feed_impressions (user_id);
create index if not exists idx_user_feed_events_user on public.user_feed_events (user_id);
create index if not exists idx_reports_reporter on public.reports (reporter_id);

