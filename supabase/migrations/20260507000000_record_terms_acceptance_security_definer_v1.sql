-- UGC moderation: harden record_terms_acceptance_v1 against permission denied
-- errors. The RPC needs to UPDATE user_terms_acceptances on conflict (so the
-- accepted_at / device metadata refresh on re-acceptance), but the
-- `authenticated` role only has INSERT/SELECT grants and there is no UPDATE
-- RLS policy. Running as SECURITY DEFINER lets the function manage the table
-- on the user's behalf while still validating auth.uid() and only ever
-- writing the caller's own row.

-- Drop and re-create with SECURITY DEFINER. Re-grant execute to authenticated.
drop function if exists public.record_terms_acceptance_v1(text, text, text);

create or replace function public.record_terms_acceptance_v1(
  p_app_version text default null,
  p_build_number text default null,
  p_device_info text default null
)
returns uuid
language plpgsql
security definer
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

revoke all on function public.record_terms_acceptance_v1(text, text, text) from public;
grant execute on function public.record_terms_acceptance_v1(text, text, text) to authenticated;

comment on function public.record_terms_acceptance_v1(text, text, text) is
  'Records the calling user''s acceptance of the active terms_versions row. '
  'SECURITY DEFINER so it can perform the ON CONFLICT DO UPDATE without an '
  'UPDATE RLS policy; only ever writes auth.uid() rows.';
