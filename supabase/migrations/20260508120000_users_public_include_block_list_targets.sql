-- Blocked users must still appear in `users_public` for the *blocker* so Settings → Blocked Users
-- can load id/username/avatar. The default rule hid them because `user_has_block_between` is true.

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
    or exists (
      select 1
      from public.user_blocks ub
      where ub.blocker_id = (select auth.uid())
        and ub.blocked_user_id = u.id
    )
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
