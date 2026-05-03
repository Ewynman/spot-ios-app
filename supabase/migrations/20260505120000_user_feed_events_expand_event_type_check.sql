-- Align user_feed_events.event_type with iOS FeedEventType wire values.
-- Inserts were failing with: violates check constraint "user_feed_events_event_type_check"
-- for event types such as map_pin_tap (and vibe_tap, unfollow_author) added on the client
-- before the DB allow-list was updated.

alter table public.user_feed_events
  drop constraint if exists user_feed_events_event_type_check;

alter table public.user_feed_events
  add constraint user_feed_events_event_type_check
  check (
    event_type = any (
      array[
        'block_author',
        'detail_open',
        'follow_author',
        'hide',
        'impression',
        'like',
        'long_dwell',
        'map_pin_tap',
        'profile_tap',
        'quick_skip',
        'report',
        'save',
        'share',
        'unfollow_author',
        'unlike',
        'unsave',
        'vibe_tap',
        'visible_2s'
      ]::text[]
    )
  );
