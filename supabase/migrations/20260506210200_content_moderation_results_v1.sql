-- UGC moderation: results from content filtering pipelines.
--
-- Stores per-target moderation outcomes from text/image/mixed filters so we
-- can enforce server-side rules and audit how content was classified. Image
-- moderation already lives in `media_assets`; this table covers text and any
-- future custom checks (profile fields, captions, etc).

create table if not exists public.content_moderation_results (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in (
    'spot',
    'spot_image',
    'profile',
    'comment',
    'collection',
    'other'
  )),
  target_id uuid not null,
  user_id uuid references auth.users(id) on delete set null,
  input_type text not null check (input_type in ('text', 'image', 'mixed')),
  status text not null check (status in (
    'approved',
    'flagged',
    'rejected',
    'pending_review'
  )),
  categories jsonb not null default '{}'::jsonb,
  matched_terms text[],
  provider text not null default 'spot_internal',
  provider_response jsonb,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewer_user_id uuid references auth.users(id) on delete set null,
  reviewer_notes text
);

comment on table public.content_moderation_results is
  'Per-target results from text/profile content filtering. Service-role/admin only.';

create index if not exists content_moderation_results_target_idx
  on public.content_moderation_results (target_type, target_id);

create index if not exists content_moderation_results_status_created_idx
  on public.content_moderation_results (status, created_at desc);

alter table public.content_moderation_results enable row level security;

revoke all on public.content_moderation_results from public;
revoke all on public.content_moderation_results from authenticated;
revoke all on public.content_moderation_results from anon;
