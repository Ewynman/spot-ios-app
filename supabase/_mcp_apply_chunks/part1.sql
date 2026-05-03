-- Azure Content Safety image moderation (v1): media_assets, buckets, RLS,
-- publish_spot_with_approved_media_assets_v1, storage policies, legacy backfill.
--
-- NOTE: This file is the source of truth. It was applied to production in parts
-- via Supabase MCP apply_migration (image_moderation_azure_v1_part{1,2,3}).

-- ---------------------------------------------------------------------------
-- 1. Storage buckets (private)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('pending_images', 'pending_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[]),
  ('approved_spot_images', 'approved_spot_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[]),
  ('approved_profile_images', 'approved_profile_images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 2. Core tables
-- ---------------------------------------------------------------------------
create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('spot_image', 'profile_image')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'failed', 'deleted', 'legacy_unmoderated')),
  pending_bucket text,
  pending_path text,
  approved_bucket text,
  approved_path text,
  linked_spot_id uuid references public.spots (id) on delete set null,
  mime_type text,
  byte_size integer,
  width integer,
  height integer,
  sha256 text,
  scores jsonb not null default '{}'::jsonb,
  azure_result jsonb,
  rejection_reason text,
  moderation_provider text not null default 'azure_content_safety',
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint media_assets_pending_path_required check (
    status = 'deleted'
    or pending_path is not null
    or approved_path is not null
  )
);

create unique index if not exists media_assets_approved_location_uniq
  on public.media_assets (approved_bucket, approved_path)
  where approved_path is not null and approved_bucket is not null;

create index if not exists media_assets_owner_status_idx
  on public.media_assets (owner_id, status);

create index if not exists media_assets_kind_status_idx
  on public.media_assets (kind, status);

create index if not exists media_assets_created_at_idx
  on public.media_assets (created_at desc);

create index if not exists media_assets_linked_spot_idx
  on public.media_assets (linked_spot_id)
  where linked_spot_id is not null;

create table if not exists public.media_moderation_events (
  id uuid primary key default gen_random_uuid(),
  media_asset_id uuid not null references public.media_assets (id) on delete cascade,
  actor_user_id uuid references auth.users (id) on delete set null,
  provider text not null default 'azure_content_safety',
  status text not null check (status in ('approved', 'rejected', 'failed')),
  scores jsonb not null default '{}'::jsonb,
  raw_result jsonb,
  reason text,
  error_code text,
  created_at timestamptz not null default now()
);

create index if not exists media_moderation_events_asset_idx
  on public.media_moderation_events (media_asset_id, created_at desc);

alter table public.spot_images
  add column if not exists media_asset_id uuid references public.media_assets (id) on delete set null;

alter table public.spot_images
  add column if not exists storage_bucket text not null default 'spots';

comment on column public.spot_images.storage_bucket is
  'Supabase Storage bucket id for storage_path (default spots; moderated posts use approved_spot_images).';
