-- UGC moderation: append-only audit trail for safety events.
--
-- Captures every report, block, content removal, suspension, ban, and similar
-- moderation event so Eddie / future moderators can review what happened on a
-- per-user / per-target basis. Insert path is locked to service role + RPCs;
-- regular users never read this table.

create table if not exists public.moderation_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in (
    'report_created',
    'user_blocked',
    'content_filter_rejected',
    'content_filter_flagged',
    'content_removed',
    'user_warned',
    'user_suspended',
    'user_banned',
    'report_resolved'
  )),
  actor_user_id uuid references auth.users(id) on delete set null,
  subject_user_id uuid references auth.users(id) on delete set null,
  target_type text,
  target_id uuid,
  report_id uuid references public.reports(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.moderation_events is
  'Append-only audit log for moderation/safety events. Inserted by RPCs and triggers; never readable by end users.';

create index if not exists moderation_events_created_at_idx
  on public.moderation_events (created_at desc);

create index if not exists moderation_events_type_created_idx
  on public.moderation_events (event_type, created_at desc);

create index if not exists moderation_events_subject_user_idx
  on public.moderation_events (subject_user_id, created_at desc)
  where subject_user_id is not null;

create index if not exists moderation_events_target_idx
  on public.moderation_events (target_type, target_id)
  where target_id is not null;

alter table public.moderation_events enable row level security;

-- Lock the table down: no end-user access. Inserts happen via SECURITY DEFINER
-- functions / triggers, and reads are restricted to service role.
revoke all on public.moderation_events from public;
revoke all on public.moderation_events from authenticated;
revoke all on public.moderation_events from anon;
