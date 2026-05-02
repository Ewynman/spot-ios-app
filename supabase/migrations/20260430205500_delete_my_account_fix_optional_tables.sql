-- Fix `delete_my_account()` for the current Supabase schema:
-- - `public.reports` is optional and does not exist in the current project.
-- - `auth.refresh_tokens.user_id` is text/varchar in GoTrue, not uuid.

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Avoid hanging forever behind another session's row locks.
  PERFORM set_config('lock_timeout', '5s', true);

  DELETE FROM public.user_feed_events WHERE user_id = uid;
  DELETE FROM public.feed_impressions
  WHERE user_id = uid
     OR spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.user_vibe_affinities WHERE user_id = uid;
  DELETE FROM public.user_creator_affinities WHERE user_id = uid;
  DELETE FROM public.user_feed_profiles WHERE user_id = uid;
  DELETE FROM public.user_hidden_spots WHERE user_id = uid;

  DELETE FROM public.follows WHERE follower_id = uid OR followee_id = uid;
  DELETE FROM public.follow_requests WHERE requester_id = uid OR target_user_id = uid;
  DELETE FROM public.user_blocks WHERE blocker_id = uid OR blocked_user_id = uid;

  DELETE FROM public.spot_likes WHERE user_id = uid;
  DELETE FROM public.spot_bookmarks WHERE user_id = uid;

  IF to_regclass('public.reports') IS NOT NULL THEN
    EXECUTE '
      DELETE FROM public.reports
      WHERE reporter_id = $1
         OR owner_id = $1
         OR spot_id IN (SELECT id FROM public.spots WHERE user_id = $1)
    ' USING uid;
  END IF;

  DELETE FROM public.bookmark_collection_spots
  WHERE collection_id IN (SELECT id FROM public.bookmark_collections WHERE user_id = uid);
  DELETE FROM public.bookmark_collections WHERE user_id = uid;

  DELETE FROM public.spot_likes WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.spot_bookmarks WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.feed_impressions WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.user_feed_events WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);

  DELETE FROM public.spot_images WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.spots WHERE user_id = uid;

  DELETE FROM public.users WHERE id = uid;

  DELETE FROM auth.refresh_tokens
  WHERE user_id = uid::text
     OR session_id IN (SELECT id FROM auth.sessions WHERE user_id = uid);
  DELETE FROM auth.sessions WHERE user_id = uid;
  DELETE FROM auth.identities WHERE user_id = uid;
  DELETE FROM auth.users WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMENT ON FUNCTION public.delete_my_account() IS 'Deletes the authenticated user''s app data and auth user. Skips optional tables absent from this project. Storage blobs are purged separately by the client.';
