-- Enforce at most one follow row per (follower_id, followee_id).
-- Dedupe historical duplicates (if any) before creating the unique index.

delete from public.follows a
  using public.follows b
 where a.ctid > b.ctid
   and a.follower_id = b.follower_id
   and a.followee_id = b.followee_id;

create unique index if not exists follows_follower_followee_uidx
  on public.follows (follower_id, followee_id);
