-- UGC moderation: typed RPCs for report submission, blocking, and terms
-- acceptance. These wrap direct table inserts with priority assignment,
-- atomicity, and well-defined contracts the iOS client can rely on.

-- Map a report reason to a moderation queue priority bucket.
create or replace function public.priority_for_report_reason(p_reason text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(p_reason, ''))
    when 'violence' then 'urgent'
    when 'violence_or_threats' then 'urgent'
    when 'illegal' then 'urgent'
    when 'illegal_content' then 'urgent'
    when 'misinformation' then 'high'
    when 'privacy' then 'high'
    when 'private_information' then 'high'
    when 'inappropriate' then 'high'
    when 'sexual_or_nude_content' then 'high'
    when 'harassment' then 'high'
    when 'harassment_or_abuse' then 'high'
    when 'hate_speech_or_discrimination' then 'high'
    when 'spam' then 'normal'
    when 'spam_or_scam' then 'normal'
    else 'normal'
  end;
$$;

-- submit_content_report: create a report row + moderation event in a single
-- statement. Returns the new report id. Honors RLS by always setting
-- reporter_id from auth.uid().
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
security invoker
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

grant execute on function public.submit_content_report(text, uuid, uuid, text, text, boolean) to authenticated;

-- block_user_v1: creates the user_blocks row (idempotent). The existing
-- after-insert trigger handles moderation_event logging.
create or replace function public.block_user_v1(
  p_blocked_user_id uuid,
  p_source_target_type text default null,
  p_source_target_id uuid default null,
  p_reason text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_block_id uuid;
  v_existing_id uuid;
begin
  if auth.uid() is null then
    raise exception 'block_user_v1 requires authentication';
  end if;

  if p_blocked_user_id is null then
    raise exception 'blocked_user_id is required';
  end if;

  if p_blocked_user_id = auth.uid() then
    raise exception 'cannot block yourself';
  end if;

  -- Idempotent: if already blocked, return the existing row id.
  select ub.id
    into v_existing_id
    from public.user_blocks ub
   where ub.blocker_id = auth.uid()
     and ub.blocked_user_id = p_blocked_user_id
   limit 1;
  if v_existing_id is not null then
    return v_existing_id;
  end if;

  insert into public.user_blocks (blocker_id, blocked_user_id)
  values (auth.uid(), p_blocked_user_id)
  returning id into v_block_id;

  -- Log additional metadata (block source) onto the moderation event the
  -- after-insert trigger created. We append a follow-up event with the
  -- caller-provided context so we don't fight the trigger's primary row.
  if p_source_target_type is not null or p_reason is not null then
    insert into public.moderation_events (
      event_type,
      actor_user_id,
      subject_user_id,
      target_type,
      target_id,
      metadata
    ) values (
      'user_blocked',
      auth.uid(),
      p_blocked_user_id,
      coalesce(p_source_target_type, 'profile'),
      coalesce(p_source_target_id, p_blocked_user_id),
      jsonb_build_object(
        'source', 'block_user_v1_rpc',
        'reason', coalesce(p_reason, ''),
        'block_id', v_block_id
      )
    );
  end if;

  return v_block_id;
end;
$$;

grant execute on function public.block_user_v1(uuid, text, uuid, text) to authenticated;

-- record_terms_acceptance_v1: mark the active terms version as accepted by
-- the calling user. Returns the terms_version_id that was recorded.
create or replace function public.record_terms_acceptance_v1(
  p_app_version text default null,
  p_build_number text default null,
  p_device_info text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_version_id uuid;
begin
  if v_user_id is null then
    raise exception 'record_terms_acceptance_v1 requires authentication';
  end if;

  select tv.id
    into v_version_id
    from public.terms_versions tv
   where tv.is_active = true
   order by tv.effective_at desc
   limit 1;

  if v_version_id is null then
    raise exception 'no active terms_versions row';
  end if;

  insert into public.user_terms_acceptances (
    user_id,
    terms_version_id,
    platform,
    app_version,
    build_number,
    device_info
  ) values (
    v_user_id,
    v_version_id,
    'ios',
    p_app_version,
    p_build_number,
    p_device_info
  )
  on conflict (user_id, terms_version_id) do update
    set accepted_at = now(),
        platform = excluded.platform,
        app_version = excluded.app_version,
        build_number = excluded.build_number,
        device_info = excluded.device_info;

  return v_version_id;
end;
$$;

grant execute on function public.record_terms_acceptance_v1(text, text, text) to authenticated;

-- has_accepted_active_terms: read-only helper for the iOS client to check if
-- the calling user has already accepted the latest active terms version.
create or replace function public.has_accepted_active_terms()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from public.terms_versions tv
    join public.user_terms_acceptances uta
      on uta.terms_version_id = tv.id
     and uta.user_id = (select auth.uid())
    where tv.is_active = true
  );
$$;

grant execute on function public.has_accepted_active_terms() to authenticated;
