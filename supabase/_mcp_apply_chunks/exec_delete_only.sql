-- 10. delete_my_account: purge media rows before spots
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  perform set_config('lock_timeout', '5s', true);

  delete from public.user_feed_events where user_id = uid;
  delete from public.feed_impressions
  where user_id = uid
     or spot_id in (select id from public.spots where user_id = uid);
  delete from public.user_vibe_affinities where user_id = uid;
  delete from public.user_creator_affinities where user_id = uid;
  delete from public.user_feed_profiles where user_id = uid;
  delete from public.user_hidden_spots where user_id = uid;

  delete from public.follows where follower_id = uid or followee_id = uid;
  delete from public.follow_requests where requester_id = uid or target_user_id = uid;
  delete from public.user_blocks where blocker_id = uid or blocked_user_id = uid;

  delete from public.spot_likes where user_id = uid;
  delete from public.spot_bookmarks where user_id = uid;

  if to_regclass('public.reports') is not null then
    execute '
      delete from public.reports
      where reporter_id = $1
         or owner_id = $1
         or spot_id in (select id from public.spots where user_id = $1)
    ' using uid;
  end if;

  delete from public.bookmark_collection_spots
  where collection_id in (select id from public.bookmark_collections where user_id = uid);
  delete from public.bookmark_collections where user_id = uid;

  delete from public.spot_likes where spot_id in (select id from public.spots where user_id = uid);
  delete from public.spot_bookmarks where spot_id in (select id from public.spots where user_id = uid);
  delete from public.feed_impressions where spot_id in (select id from public.spots where user_id = uid);
  delete from public.user_feed_events where spot_id in (select id from public.spots where user_id = uid);

  update public.spot_images si
  set media_asset_id = null
  from public.spots s
  where si.spot_id = s.id
    and s.user_id = uid;

  update public.users
  set profile_image_asset_id = null
  where id = uid;

  delete from public.media_assets where owner_id = uid;

  delete from public.spot_images where spot_id in (select id from public.spots where user_id = uid);
  delete from public.spots where user_id = uid;

  delete from public.users where id = uid;

  delete from auth.refresh_tokens
  where user_id = uid::text
     or session_id in (select id from auth.sessions where user_id = uid);
  delete from auth.sessions where user_id = uid;
  delete from auth.identities where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Deletes the authenticated user''s app data and auth user. Purges media_assets. Storage blobs are purged separately by the client.';