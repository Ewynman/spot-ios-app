-- 1) Ensure authenticated can upsert `public.users` (syncCurrentUser) — idempotent grants.
grant usage on schema public to authenticated;
grant select, insert, delete on table public.users to authenticated;

-- Column-scoped UPDATE was already applied in the security sweep; re-assert so merges from
-- partial environments still match the app upsert (email, username, last_active_at, locale, …).
revoke update on table public.users from authenticated;
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

-- 2) Explicit DML on user_blocks (RLS still gates rows; some DBs had no table GRANT after default-privilege revokes).
grant select, insert, delete on table public.user_blocks to authenticated;

-- 3) Allow "I block them" even when they already blocked you (reverse row exists).
-- The old check used user_has_block_between(), which forbade any pair with an existing row in either direction.
drop policy if exists user_blocks_insert_own on public.user_blocks;

create policy user_blocks_insert_own
  on public.user_blocks
  for insert
  to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocker_id <> blocked_user_id
    and not exists (
      select 1
      from public.user_blocks ub
      where ub.blocker_id = (select auth.uid())
        and ub.blocked_user_id = blocked_user_id
    )
  );
