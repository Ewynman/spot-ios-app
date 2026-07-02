-- Fix: returning users' profile sync fails with "permission denied for table
-- users" (SQLSTATE 42501).
--
-- Root cause: the client called PostgREST upsert on public.users with
-- onConflict "id", which compiles to
--   INSERT ... ON CONFLICT (id) DO UPDATE SET id = excluded.id, ...
-- The `authenticated` role intentionally has only column-scoped UPDATE on
-- public.users (every mutable column EXCEPT `id`, so users can never rewrite
-- their own primary key). Because the generated ON CONFLICT DO UPDATE includes
-- `id` in its SET list, Postgres denies the whole statement for existing rows.
-- New users worked (INSERT branch), but every returning user's sync failed.
--
-- Fix: move the write into a SECURITY DEFINER RPC that derives the row id from
-- auth.uid() (never trusting a client-supplied id) and only ever writes the
-- caller's own row. The function is owned by `postgres` (BYPASSRLS + full
-- table UPDATE), so it performs the ON CONFLICT DO UPDATE without needing a
-- table-wide UPDATE grant on the `authenticated` role.
--
-- Semantics: on first sync (INSERT) the full profile is written. On conflict we
-- only refresh login/heartbeat fields (email, email_verified, last_active_at,
-- locale). User-managed fields (username, username_lower, is_private,
-- profile_image_url, is_pro, pro_until) are preserved so a login-time sync can
-- never clobber a Settings change or overwrite a real username with a
-- login-derived fallback.

create or replace function public.sync_current_user_v1(
  p_username text,
  p_username_lower text,
  p_email text default null,
  p_email_verified boolean default false,
  p_is_private boolean default false,
  p_locale text default null,
  p_last_active_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := coalesce(p_last_active_at, now());
begin
  if v_user_id is null then
    raise exception 'sync_current_user_v1 requires authentication';
  end if;

  if p_username is null or length(btrim(p_username)) = 0
     or p_username_lower is null or length(btrim(p_username_lower)) = 0 then
    raise exception 'sync_current_user_v1 requires a non-empty username';
  end if;

  insert into public.users (
    id,
    email,
    email_verified,
    username,
    username_lower,
    is_private,
    last_active_at,
    locale
  ) values (
    v_user_id,
    p_email,
    coalesce(p_email_verified, false),
    p_username,
    p_username_lower,
    coalesce(p_is_private, false),
    v_now,
    p_locale
  )
  on conflict (id) do update
    set email = excluded.email,
        email_verified = excluded.email_verified,
        last_active_at = excluded.last_active_at,
        locale = excluded.locale,
        updated_at = now();

  return v_user_id;
end;
$$;

revoke all on function public.sync_current_user_v1(text, text, text, boolean, boolean, text, timestamptz) from public;
grant execute on function public.sync_current_user_v1(text, text, text, boolean, boolean, text, timestamptz) to authenticated;

comment on function public.sync_current_user_v1(text, text, text, boolean, boolean, text, timestamptz) is
  'Upserts the calling user''s public.users row (id = auth.uid()). SECURITY '
  'DEFINER so the ON CONFLICT DO UPDATE can run without a table-wide UPDATE '
  'grant on authenticated (which lacks UPDATE on id). On conflict only '
  'login/heartbeat fields refresh; username, is_private, and avatar are '
  'preserved. Only ever writes the caller''s own row.';
