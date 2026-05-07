-- UGC moderation: keep `moderation_events` populated automatically.
--
-- Adds AFTER INSERT triggers that mirror every report and every block into
-- `public.moderation_events`. This guarantees the audit log is updated even
-- when client code inserts directly into `reports` / `user_blocks` (the
-- existing ReportSheet and AuthViewModel paths) instead of going through the
-- new RPCs.

create or replace function public.fn_log_moderation_event_for_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.moderation_events (
    event_type,
    actor_user_id,
    subject_user_id,
    target_type,
    target_id,
    report_id,
    metadata
  ) values (
    'report_created',
    NEW.reporter_id,
    NEW.owner_id,
    coalesce(NEW.target_type, 'spot'),
    coalesce(NEW.target_id, NEW.spot_id),
    NEW.id,
    jsonb_build_object(
      'reason', NEW.reason,
      'priority', coalesce(NEW.priority, 'normal'),
      'block_requested', coalesce(NEW.block_requested, false),
      'platform', NEW.platform,
      'app_version', NEW.app_version
    )
  );
  return NEW;
end;
$$;

drop trigger if exists trg_log_moderation_event_for_report on public.reports;
create trigger trg_log_moderation_event_for_report
  after insert on public.reports
  for each row
  execute function public.fn_log_moderation_event_for_report();

create or replace function public.fn_log_moderation_event_for_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.moderation_events (
    event_type,
    actor_user_id,
    subject_user_id,
    target_type,
    target_id,
    metadata
  ) values (
    'user_blocked',
    NEW.blocker_id,
    NEW.blocked_user_id,
    'profile',
    NEW.blocked_user_id,
    jsonb_build_object('source', 'user_blocks_insert')
  );
  return NEW;
end;
$$;

drop trigger if exists trg_log_moderation_event_for_block on public.user_blocks;
create trigger trg_log_moderation_event_for_block
  after insert on public.user_blocks
  for each row
  execute function public.fn_log_moderation_event_for_block();
