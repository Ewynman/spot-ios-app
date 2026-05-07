-- UGC moderation: read-only queue view for moderators.
--
-- Aggregates open + reviewing reports with the priority-first ordering
-- requested in the PRD. Service-role only — the underlying tables already
-- block end users from reading reports/moderation_events.

create or replace view public.moderation_queue as
select
  r.id,
  r.status,
  r.priority,
  r.reason,
  r.target_type,
  coalesce(r.target_id, r.spot_id) as target_id,
  r.spot_id,
  r.owner_id as reported_user_id,
  r.reporter_id,
  r.created_at,
  r.details,
  r.block_requested,
  r.platform,
  r.app_version
from public.reports r
where r.status in ('open', 'reviewing')
order by
  case r.priority
    when 'urgent' then 1
    when 'high' then 2
    when 'normal' then 3
    else 4
  end,
  r.created_at asc;

comment on view public.moderation_queue is
  'Service-role moderation queue: open + reviewing reports ordered by priority and age.';

revoke all on public.moderation_queue from public;
revoke all on public.moderation_queue from authenticated;
revoke all on public.moderation_queue from anon;
