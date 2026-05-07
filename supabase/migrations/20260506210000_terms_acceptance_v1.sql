-- UGC moderation: terms versions and per-user acceptance records.
--
-- Adds two additive tables:
--   * `terms_versions`         — catalog of legal/moderation terms releases.
--   * `user_terms_acceptances` — proof a given user accepted a specific version.
--
-- Both are RLS-locked to the owning user (or service role for admin work).
-- A seed row is inserted for the active 2026-05-ugc-moderation release so the
-- iOS Terms gate has something to read on day one.

create table if not exists public.terms_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  title text not null,
  terms_url text not null,
  privacy_url text not null,
  is_active boolean not null default false,
  effective_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.terms_versions is
  'Active and historical Terms of Use / Privacy Policy releases. Only one row should be is_active = true at a time.';

create unique index if not exists terms_versions_one_active
  on public.terms_versions ((is_active))
  where is_active;

alter table public.terms_versions enable row level security;

drop policy if exists terms_versions_select_active on public.terms_versions;
create policy terms_versions_select_active
  on public.terms_versions
  for select
  to authenticated, anon
  using (is_active = true);

create table if not exists public.user_terms_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version_id uuid not null references public.terms_versions(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  platform text not null default 'ios',
  app_version text,
  build_number text,
  device_info text,
  created_at timestamptz not null default now(),
  unique (user_id, terms_version_id)
);

comment on table public.user_terms_acceptances is
  'Proof of consent: each row marks a single user accepting a specific terms_versions row.';

create index if not exists user_terms_acceptances_user_idx
  on public.user_terms_acceptances (user_id, accepted_at desc);

alter table public.user_terms_acceptances enable row level security;

drop policy if exists user_terms_acceptances_insert_own on public.user_terms_acceptances;
create policy user_terms_acceptances_insert_own
  on public.user_terms_acceptances
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_terms_acceptances_select_own on public.user_terms_acceptances;
create policy user_terms_acceptances_select_own
  on public.user_terms_acceptances
  for select
  to authenticated
  using (user_id = (select auth.uid()));

grant select on public.terms_versions to authenticated, anon;
grant insert, select on public.user_terms_acceptances to authenticated;

-- Seed the current active terms release. Idempotent on (version).
insert into public.terms_versions (version, title, terms_url, privacy_url, is_active, effective_at)
values (
  '2026-05-ugc-moderation',
  'Spot Terms of Use - UGC Moderation Update',
  'https://spotapp.online/terms',
  'https://spotapp.online/privacy',
  true,
  '2026-05-06 00:00:00+00'
)
on conflict (version) do update
  set title = excluded.title,
      terms_url = excluded.terms_url,
      privacy_url = excluded.privacy_url,
      is_active = true,
      effective_at = excluded.effective_at;
