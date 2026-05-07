-- UGC moderation: allow non-spot reports.
--
-- The original `reports` schema (legacy) makes `spot_id` NOT NULL with an FK
-- to `public.spots(id)`. The first cut of the moderation extension (see
-- `20260506210600_reports_target_extension_v1.sql`) tried to satisfy that by
-- setting `spot_id = target_id` for `target_type = 'profile'`, but the FK
-- still rejects those rows because a user UUID is not a spot UUID.
--
-- This migration:
--   1. Drops the NOT NULL on `reports.spot_id` so non-spot reports can omit
--      it (the FK already permits NULL — it only rejects non-existent spot
--      IDs).
--   2. Adds a CHECK constraint requiring spot_id to be set for spot reports
--      so the legacy invariant for `target_type = 'spot'` is preserved.
--   3. Replaces the `reports_insert_own` RLS policy with one that no longer
--      requires `spot_id = target_id` for non-spot reports.
--   4. Re-creates `submit_content_report` to insert NULL into `spot_id` for
--      non-spot reports while still resolving spot reports through the live
--      `spots` row (preserving the old behavior).

-- 1. Make spot_id nullable.
alter table public.reports
  alter column spot_id drop not null;

-- 2. Require spot_id when target_type = 'spot' (preserves legacy invariant).
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_spot_target_has_spot_id'
  ) then
    alter table public.reports
      add constraint reports_spot_target_has_spot_id
      check (target_type <> 'spot' or spot_id is not null);
  end if;
end$$;

-- 3. Refresh RLS so profile reports no longer have to fake a spot_id.
drop policy if exists reports_insert_own on public.reports;

create policy reports_insert_own
  on public.reports
  for insert
  to authenticated
  with check (
    reporter_id = (select auth.uid())
    and reporter_id <> owner_id
    and (
      (
        target_type = 'spot'
        and spot_id is not null
        and owner_id = (
          select s.user_id
          from public.spots s
          where s.id = spot_id
        )
      )
      or (
        target_type = 'profile'
        and owner_id = target_id
        and spot_id is null
      )
      or (
        target_type in ('spot_image', 'comment', 'collection', 'other')
        and target_id is not null
        and spot_id is null
      )
    )
  );

-- 4. Re-create submit_content_report so it never tries to set spot_id for
--    non-spot reports. The function stays SECURITY DEFINER (per
--    20260507000100_submit_content_report_security_definer_v1.sql) so the
--    INSERT ... RETURNING continues to work.
drop function if exists public.submit_content_report(text, uuid, uuid, text, text, boolean);

create or replace function public.submit_content_report(
  p_target_type text,
  p_target_id uuid,
  p_reported_user_id uuid,
  p_reason text,
  p_details text default '',
  p_block_requested boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report_id uuid;
  v_priority text;
  v_owner uuid;
  v_spot_id uuid;
begin
  if auth.uid() is null then
    raise exception 'submit_content_report requires authentication';
  end if;

  if p_target_type is null or p_target_type = '' then
    raise exception 'target_type is required';
  end if;

  if p_target_id is null then
    raise exception 'target_id is required';
  end if;

  if p_reason is null or p_reason = '' then
    raise exception 'reason is required';
  end if;

  v_priority := public.priority_for_report_reason(p_reason);

  if p_target_type = 'spot' then
    select s.user_id, s.id
      into v_owner, v_spot_id
      from public.spots s
     where s.id = p_target_id;
    if v_owner is null then
      raise exception 'spot not found for report target_id %', p_target_id;
    end if;
  elsif p_target_type = 'profile' then
    -- Profile reports: owner_id = reported user, spot_id stays NULL.
    v_owner := coalesce(p_reported_user_id, p_target_id);
    v_spot_id := null;
  else
    -- spot_image / comment / collection / other: trust caller-provided
    -- reported_user_id if available, else fall back to target_id. spot_id
    -- stays NULL so we don't violate the FK.
    v_owner := coalesce(p_reported_user_id, p_target_id);
    v_spot_id := null;
  end if;

  if v_owner = auth.uid() then
    raise exception 'cannot report your own content';
  end if;

  insert into public.reports (
    spot_id,
    reporter_id,
    owner_id,
    reason,
    details,
    platform,
    app_version,
    block_requested,
    target_type,
    target_id,
    status,
    priority
  ) values (
    v_spot_id,
    auth.uid(),
    v_owner,
    p_reason,
    coalesce(p_details, ''),
    'ios',
    coalesce(current_setting('request.jwt.claim.app_version', true), 'unknown'),
    coalesce(p_block_requested, false),
    p_target_type,
    p_target_id,
    'open',
    v_priority
  )
  returning id into v_report_id;

  return v_report_id;
end;
$$;

revoke all on function public.submit_content_report(text, uuid, uuid, text, text, boolean) from public;
grant execute on function public.submit_content_report(text, uuid, uuid, text, text, boolean) to authenticated;

comment on function public.submit_content_report(text, uuid, uuid, text, text, boolean) is
  'Creates a report row with priority + audit. SECURITY DEFINER so the '
  'INSERT ... RETURNING can read its own row even though authenticated only '
  'has INSERT on public.reports. spot_id is only set for target_type=''spot'' '
  'reports (resolved from public.spots). Authorization enforced via auth.uid() '
  'checks inside the function body.';
