-- UGC moderation: extend the existing `reports` table to support reporting
-- profiles/users (and other content types) without breaking the existing spot
-- reporting flow used by ReportSheet.swift.
--
-- Adds:
--   reports.target_type  ('spot' default, plus 'profile', 'spot_image', 'comment', 'collection', 'other')
--   reports.target_id    uuid (mirrors spot_id for spot reports, references the user for profile reports, etc.)
--   reports.status       moderation workflow ('open', 'reviewing', 'actioned', 'dismissed')
--   reports.priority     priority ('low', 'normal', 'high', 'urgent')
--   reports.reviewed_at, resolved_at, reviewer_user_id, reviewer_notes, action_taken
--
-- Backwards compatibility:
--   * `spot_id` stays NOT NULL (existing inserts keep working).
--   * For `target_type = 'profile'`, the existing `spot_id` column is set to
--     `reported_user_id` so the legacy NOT NULL constraint and existing RLS
--     check keep passing while still letting moderation tools group rows by
--     target via `target_type` / `target_id`.

alter table public.reports
  add column if not exists target_type text not null default 'spot',
  add column if not exists target_id uuid,
  add column if not exists status text not null default 'open',
  add column if not exists priority text not null default 'normal',
  add column if not exists reviewed_at timestamptz,
  add column if not exists resolved_at timestamptz,
  add column if not exists reviewer_user_id uuid references auth.users(id) on delete set null,
  add column if not exists reviewer_notes text,
  add column if not exists action_taken text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_target_type_check'
  ) then
    alter table public.reports
      add constraint reports_target_type_check
      check (target_type in ('spot', 'profile', 'spot_image', 'comment', 'collection', 'other'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_status_check'
  ) then
    alter table public.reports
      add constraint reports_status_check
      check (status in ('open', 'reviewing', 'actioned', 'dismissed'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_priority_check'
  ) then
    alter table public.reports
      add constraint reports_priority_check
      check (priority in ('low', 'normal', 'high', 'urgent'));
  end if;
end$$;

create index if not exists reports_status_created_at_idx
  on public.reports (status, created_at desc);

create index if not exists reports_target_idx
  on public.reports (target_type, target_id);

create index if not exists reports_owner_id_created_idx
  on public.reports (owner_id, created_at desc);

-- Backfill target_id for existing rows so the new index is useful immediately.
update public.reports
   set target_id = spot_id
 where target_id is null
   and target_type = 'spot';

-- Update the insert policy to also allow profile reports while keeping the
-- existing spot-report invariants (target_type='spot' must reference a real
-- spot whose owner matches owner_id; reporter cannot self-report).
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
        and owner_id = (
          select s.user_id
          from public.spots s
          where s.id = spot_id
        )
      )
      or (
        target_type = 'profile'
        and owner_id = target_id
        and spot_id = target_id
      )
      or (
        target_type in ('spot_image', 'comment', 'collection', 'other')
        and target_id is not null
      )
    )
  );

-- Self-reading remains disabled (no SELECT policy means service role / admin
-- only). This preserves the privacy requirement that reporter identities are
-- never exposed to reported users.

comment on column public.reports.target_type is
  'Type of content being reported: spot (default), profile, spot_image, comment, collection, other.';
comment on column public.reports.target_id is
  'UUID of the reported target. For target_type=spot this matches spot_id; for profile this matches owner_id.';
comment on column public.reports.status is
  'Moderation workflow status: open, reviewing, actioned, dismissed.';
comment on column public.reports.priority is
  'Priority bucket assigned by submit RPC based on reason. Used to prioritize the moderation queue.';
