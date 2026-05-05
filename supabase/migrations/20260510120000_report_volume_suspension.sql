-- Report-volume suspension (server-side, no Edge Function).
-- When an author receives enough distinct reports in a rolling window, set
-- users.suspended_for_reports_at so their content is hidden from feed, search,
-- and spot visibility helpers (can_view_author / users_public).

-- ---------------------------------------------------------------------------
-- 1. Column on users (not granted to client UPDATE; only trigger / admin SQL)
-- ---------------------------------------------------------------------------
alter table public.users
  add column if not exists suspended_for_reports_at timestamptz null;

comment on column public.users.suspended_for_reports_at is
  'When set, this user''s public spots/profile are hidden from discovery and home feed until cleared by support.';

create index if not exists idx_reports_owner_created_at
  on public.reports (owner_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Thresholds (tune here; document in docs/engineering/database-and-rls.md)
-- ---------------------------------------------------------------------------
-- Rolling window for counting reports against the same owner.
-- Require BOTH: enough total reports AND enough distinct reporters (anti-brigade).

create or replace function public.apply_report_volume_suspension()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := NEW.owner_id;
  v_window interval := interval '30 days';
  v_min_total integer := 5;
  v_min_distinct_reporters integer := 3;
  v_total integer;
  v_distinct integer;
begin
  select
    count(*)::integer,
    count(distinct reporter_id)::integer
  into v_total, v_distinct
  from public.reports r
  where r.owner_id = v_owner
    and r.created_at > now() - v_window;

  if v_distinct >= v_min_distinct_reporters
     and v_total >= v_min_total then
    update public.users u
    set suspended_for_reports_at = coalesce(u.suspended_for_reports_at, now())
    where u.id = v_owner
      and u.suspended_for_reports_at is null;
  end if;

  return NEW;
end;
$$;

alter function public.apply_report_volume_suspension() owner to postgres;
revoke all on function public.apply_report_volume_suspension() from public;

drop trigger if exists reports_apply_volume_suspension on public.reports;
create trigger reports_apply_volume_suspension
  after insert on public.reports
  for each row
  execute function public.apply_report_volume_suspension();

-- ---------------------------------------------------------------------------
-- 3. Hide suspended authors from visibility helpers (spots, profiles, storage paths)
-- ---------------------------------------------------------------------------
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
          and u.suspended_for_reports_at is not null
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

revoke all on function public.can_view_author(uuid) from public;
grant execute on function public.can_view_author(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. users_public: keep block-list carve-out; hide suspended from discovery leg
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
    or exists (
      select 1
      from public.user_blocks ub
      where ub.blocker_id = (select auth.uid())
        and ub.blocked_user_id = u.id
    )
    or (
      not public.user_has_block_between((select auth.uid()), u.id)
      and u.suspended_for_reports_at is null
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
