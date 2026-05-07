-- UGC moderation: per-row moderation/account state on spots and users.
--
-- Adds:
--   spots.moderation_status   ('approved' | 'flagged' | 'rejected' | 'pending_review')
--   spots.hidden_at           timestamptz when manually hidden
--   spots.hidden_reason       free-text reason for hide action
--   users.account_status      ('active' | 'restricted' | 'suspended' | 'banned')
--   users.moderation_status   ('approved' | 'flagged' | 'rejected' | 'pending_review')
--
-- Patches `can_view_spot` to also exclude rejected / pending / hidden spots
-- and accounts that are not active. The home feed RPCs inherit this via the
-- existing chain (`can_view_spot -> can_view_author`).

alter table public.spots
  add column if not exists moderation_status text not null default 'approved',
  add column if not exists hidden_at timestamptz,
  add column if not exists hidden_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.spots'::regclass
      and conname = 'spots_moderation_status_check'
  ) then
    alter table public.spots
      add constraint spots_moderation_status_check
      check (moderation_status in ('approved', 'flagged', 'rejected', 'pending_review'));
  end if;
end$$;

create index if not exists spots_moderation_status_idx
  on public.spots (moderation_status)
  where moderation_status <> 'approved';

create index if not exists spots_hidden_at_idx
  on public.spots (hidden_at)
  where hidden_at is not null;

alter table public.users
  add column if not exists account_status text not null default 'active',
  add column if not exists moderation_status text not null default 'approved';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_account_status_check'
  ) then
    alter table public.users
      add constraint users_account_status_check
      check (account_status in ('active', 'restricted', 'suspended', 'banned'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_moderation_status_check'
  ) then
    alter table public.users
      add constraint users_moderation_status_check
      check (moderation_status in ('approved', 'flagged', 'rejected', 'pending_review'));
  end if;
end$$;

create index if not exists users_account_status_idx
  on public.users (account_status)
  where account_status <> 'active';

-- Patch can_view_author to also block restricted/suspended/banned accounts.
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
      and not exists (
        select 1
        from public.users u
        where u.id = p_author
          and (
            u.suspended_for_reports_at is not null
            or coalesce(u.account_status, 'active') in ('suspended', 'banned')
          )
      )
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

-- Patch can_view_spot so rejected/hidden/pending spots fall out of every
-- query that goes through RLS or the helper (feed, map, profile, search).
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
      and s.hidden_at is null
      and coalesce(s.moderation_status, 'approved') = 'approved'
      and public.can_view_author(s.user_id)
  );
$$;
