-- INSERT policy on user_blocks used EXISTS (SELECT … FROM user_blocks …). Under FORCE ROW LEVEL
-- SECURITY that re-applies policies to the subquery and causes "infinite recursion detected in policy".

create or replace function public.user_blocks_duplicate_exists(p_blocker uuid, p_blocked uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where ub.blocker_id = p_blocker
      and ub.blocked_user_id = p_blocked
  );
$$;

alter function public.user_blocks_duplicate_exists(uuid, uuid) owner to postgres;
revoke all on function public.user_blocks_duplicate_exists(uuid, uuid) from public;
grant execute on function public.user_blocks_duplicate_exists(uuid, uuid) to authenticated;

drop policy if exists user_blocks_insert_own on public.user_blocks;

create policy user_blocks_insert_own
  on public.user_blocks
  for insert
  to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocker_id <> blocked_user_id
    and not public.user_blocks_duplicate_exists((select auth.uid()), blocked_user_id)
  );
