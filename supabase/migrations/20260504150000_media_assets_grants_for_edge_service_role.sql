-- Edge Function `moderate-image` uses PostgREST with the service_role key.
-- 20260504100000_image_moderation_azure_v1 only granted `media_assets` to
-- `authenticated` (client insert/select own). The service_role DB role had no
-- table GRANT, which produced: permission denied for table media_assets.
--
-- RLS still applies to anon/authenticated; service_role is used for trusted
-- server-side work (this function + moderation events writes).

grant select, insert, update, delete on table public.media_assets to service_role;
grant select, insert, update, delete on table public.media_moderation_events to service_role;
