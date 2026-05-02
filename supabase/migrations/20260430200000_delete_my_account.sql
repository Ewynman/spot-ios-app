-- Account deletion RPC invoked by the iOS app (`AuthService.deleteAccount`).
-- Run via `supabase db push` / dashboard SQL after review.
-- Deletes the caller's public data and auth rows. Storage objects (avatars / spots buckets)
-- must be purged separately via Storage API if your project keeps blobs outside Postgres.

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

  -- Personalization / feed signals
  DELETE FROM public.user_feed_events WHERE user_id = uid;
  DELETE FROM public.feed_impressions
  WHERE user_id = uid
     OR spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.user_vibe_affinities WHERE user_id = uid;
  DELETE FROM public.user_creator_affinities WHERE user_id = uid;
  DELETE FROM public.user_feed_profiles WHERE user_id = uid;
  DELETE FROM public.user_hidden_spots WHERE user_id = uid;

  -- Social graph
  DELETE FROM public.follows WHERE follower_id = uid OR followee_id = uid;
  DELETE FROM public.follow_requests WHERE requester_id = uid OR target_user_id = uid;
  DELETE FROM public.user_blocks WHERE blocker_id = uid OR blocked_user_id = uid;

  -- This user's likes/saves on any spot
  DELETE FROM public.spot_likes WHERE user_id = uid;
  DELETE FROM public.spot_bookmarks WHERE user_id = uid;

  -- Moderation rows tied to this user or their spots
  DELETE FROM public.reports
  WHERE reporter_id = uid
     OR owner_id = uid
     OR spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);

  -- Bookmark collections
  DELETE FROM public.bookmark_collection_spots
  WHERE collection_id IN (SELECT id FROM public.bookmark_collections WHERE user_id = uid);
  DELETE FROM public.bookmark_collections WHERE user_id = uid;

  -- Other users' interactions on this user's spots (before dropping spots)
  DELETE FROM public.spot_likes WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.spot_bookmarks WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.feed_impressions WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.user_feed_events WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);

  DELETE FROM public.spot_images WHERE spot_id IN (SELECT id FROM public.spots WHERE user_id = uid);
  DELETE FROM public.spots WHERE user_id = uid;

  DELETE FROM public.users WHERE id = uid;

  -- Auth session + user (sessions first so refresh_tokens/session FKs clean up)
  DELETE FROM auth.sessions WHERE user_id = uid;
  DELETE FROM auth.identities WHERE user_id = uid;
  DELETE FROM auth.users WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMENT ON FUNCTION public.delete_my_account() IS 'Deletes the authenticated user''s app data and auth user. Apply only after confirming RLS and FKs; purge Storage blobs separately if needed.';
