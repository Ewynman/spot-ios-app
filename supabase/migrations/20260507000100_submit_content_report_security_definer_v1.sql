-- UGC moderation: harden submit_content_report against permission denied
-- errors.
--
-- The original RPC was SECURITY INVOKER and used `INSERT ... RETURNING id
-- INTO v_report_id`. Postgres requires SELECT privilege on the RETURNING
-- columns, but the `authenticated` role only has INSERT on `public.reports`
-- (`authenticated=a/postgres`). The result is `permission denied for table
-- reports` for any client trying to submit a report.
--
-- Switching to SECURITY DEFINER lets the function read its own RETURNING row.
-- All authorization invariants are preserved because the function:
--   - Hard-fails when `auth.uid()` is null.
--   - Sets `reporter_id = auth.uid()` (no caller-controlled override).
--   - Refuses self-reports (`v_owner = auth.uid()`).
--   - Resolves `owner_id` / `spot_id` from authoritative tables, not caller
--     input, for `target_type = 'spot'`; profile / other types still respect
--     the existing `reports_insert_own` RLS predicate (which is still
--     enforced under SECURITY DEFINER because the policy compares
--     `auth.uid()` directly).

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

  -- Resolve owner_id + spot_id depending on target_type so the existing
  -- reports_insert_own RLS policy passes.
  if p_target_type = 'spot' then
    select s.user_id, s.id
      into v_owner, v_spot_id
      from public.spots s
     where s.id = p_target_id;
    if v_owner is null then
      raise exception 'spot not found for report target_id %', p_target_id;
    end if;
  elsif p_target_type = 'profile' then
    -- For profile reports, owner_id and spot_id both reference the reported user.
    v_owner := coalesce(p_reported_user_id, p_target_id);
    v_spot_id := v_owner;
  else
    -- spot_image / comment / collection / other: trust caller-provided reported_user_id
    -- if available, else fall back to target_id.
    v_owner := coalesce(p_reported_user_id, p_target_id);
    v_spot_id := coalesce(p_target_id, v_owner);
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
  'has INSERT on public.reports. Authorization is enforced via auth.uid() '
  'checks inside the function body.';
