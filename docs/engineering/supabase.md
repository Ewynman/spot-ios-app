# Supabase

## Purpose

Explain how Supabase fits into Spot: Auth, Postgres, Storage, Edge Functions, and migrations.

## Audience

Engineers touching data or backend.

## Current status

Client: `Spot/Supabase/Supabase.swift`, `SpotSupabaseRepository`. Schema evolution: `supabase/migrations/*.sql`.

## Details

### Role in architecture

Supabase is the **primary backend**: authentication, relational data for users/spots/social graph, storage for images, and RPCs such as **`get_home_feed_v1`** and **`publish_spot_with_approved_media_assets_v1`**.

**Policy:** Firebase must not be used for the application data plane. See [data-plane.md](data-plane.md).

### Auth

Supabase Auth issues JWTs consumed by the Swift client; `public.users` and related tables tie profiles to `auth.users`.

### Database

Postgres with RLS policies defined in migrations (e.g. `20260502120000_security_sweep_rls_part_1.sql`, moderation migration).

### Storage

Private buckets for pending and approved images (`pending_images`, `approved_spot_images`, `approved_profile_images`) per `20260504100000_image_moderation_azure_v1.sql`.

### Edge Functions

Image moderation pipeline references Edge Function **`moderate-image`** in repository comments—**TODO: verify** deployed function names and secrets in Supabase dashboard.

### Local vs production

- **Production**: project matching deployed `Info.plist` values for your build flavor.
- **Local Supabase**: optional CLI for schema iteration—**TODO: verify** if team uses local stack or remote dev project only.

### MCP

Cursor may use Supabase MCP for migrations in some workflows; production changes still go through reviewed SQL migrations in `supabase/migrations/`.

### Safety for schema changes

1. Never weaken RLS without security review.
2. Prefer additive migrations and backfills.
3. Test policies with non-owner sessions.

## Related docs

- [data-plane.md](data-plane.md)
- [database-and-rls.md](database-and-rls.md)
- [storage-and-media.md](storage-and-media.md)
- [image-moderation.md](image-moderation.md)

## Open questions / TODOs

- Full inventory of RPCs and Edge Functions: TODO: generate from Supabase project or SQL search.
