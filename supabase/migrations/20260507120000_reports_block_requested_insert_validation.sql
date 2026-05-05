-- Persist "also block this user" intent on the report row for moderation.
-- Tighten insert RLS: reporter must match JWT, cannot self-report, owner_id must match spot author.

alter table public.reports
  add column if not exists block_requested boolean not null default false;

drop policy if exists reports_insert_own on public.reports;

create policy reports_insert_own
  on public.reports
  for insert
  to authenticated
  with check (
    reporter_id = (select auth.uid())
    and reporter_id <> owner_id
    and owner_id = (
      select s.user_id
      from public.spots s
      where s.id = spot_id
    )
  );

comment on column public.reports.block_requested is
  'True when the reporter opted to block the spot author as part of this report; enforced client-side via blocks table.';
