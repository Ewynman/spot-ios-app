-- Patch home feed RPCs to also exclude:
--   * spots with non-approved moderation_status,
--   * spots that have been hidden (hidden_at is not null),
--   * spots whose author has account_status in (suspended, banned).
--
-- Mirrors `20260510120001_home_feed_rpc_report_suspension.sql` and uses
-- pg_get_functiondef + replace so we stay aligned with the deployed function
-- body. Skips quietly if the RPCs are missing.

DO $mig$
DECLARE
  d text;
  n text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public' AND p.proname = 'get_home_feed_v1'
  ) THEN
    RAISE NOTICE 'moderation_filter: skip get_home_feed_v1 (not installed)';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO d
  FROM pg_proc p
  JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
  WHERE nsp.nspname = 'public' AND p.proname = 'get_home_feed_v1';

  -- Inject extra filters into both `where b.author_id is null` blocks.
  n := replace(
    replace(
      d,
      $a$
          left join public.user_creator_affinities uca on uca.user_id = v_user_id and uca.creator_id = s.user_id
         where b.author_id is null
           and hs.spot_id is null
           and u.suspended_for_reports_at is null
           and (
                 s.user_id = v_user_id
$a$,
      $b$
          left join public.user_creator_affinities uca on uca.user_id = v_user_id and uca.creator_id = s.user_id
         where b.author_id is null
           and hs.spot_id is null
           and u.suspended_for_reports_at is null
           and coalesce(u.account_status, 'active') not in ('suspended', 'banned')
           and s.hidden_at is null
           and coalesce(s.moderation_status, 'approved') = 'approved'
           and (
                 s.user_id = v_user_id
$b$
    ),
    $c$
          left join public.user_hidden_spots hs on hs.user_id = v_user_id and hs.spot_id = s.id
         where b.author_id is null
           and hs.spot_id is null
           and fi.spot_id is null
           and u.suspended_for_reports_at is null
           and (
                 s.user_id = v_user_id
$c$,
    $e$
          left join public.user_hidden_spots hs on hs.user_id = v_user_id and hs.spot_id = s.id
         where b.author_id is null
           and hs.spot_id is null
           and fi.spot_id is null
           and u.suspended_for_reports_at is null
           and coalesce(u.account_status, 'active') not in ('suspended', 'banned')
           and s.hidden_at is null
           and coalesce(s.moderation_status, 'approved') = 'approved'
           and (
                 s.user_id = v_user_id
$e$
  );

  EXECUTE n;
END;
$mig$;

DO $mig$
DECLARE
  d text;
  n text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public' AND p.proname = 'get_home_feed_status_v1'
  ) THEN
    RAISE NOTICE 'moderation_filter: skip get_home_feed_status_v1 (not installed)';
    RETURN;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO d
  FROM pg_proc p
  JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
  WHERE nsp.nspname = 'public' AND p.proname = 'get_home_feed_status_v1';

  n := replace(
    d,
    $p1$
          left join public.user_hidden_spots hs on hs.user_id = v_user_id and hs.spot_id = s.id
         where b.author_id is null
           and hs.spot_id is null
           and u.suspended_for_reports_at is null
           and (
                 s.user_id = v_user_id
$p1$,
    $p2$
          left join public.user_hidden_spots hs on hs.user_id = v_user_id and hs.spot_id = s.id
         where b.author_id is null
           and hs.spot_id is null
           and u.suspended_for_reports_at is null
           and coalesce(u.account_status, 'active') not in ('suspended', 'banned')
           and s.hidden_at is null
           and coalesce(s.moderation_status, 'approved') = 'approved'
           and (
                 s.user_id = v_user_id
$p2$
  );

  EXECUTE n;
END;
$mig$;
