# Storage and media

## Purpose

Image pipeline buckets, upload flow, and signed URL usage for displaying media.

## Audience

Engineers working on posts, profiles, or moderation.

## Current status

Bucket names and `media_assets` schema are defined in **`supabase/migrations/20260504100000_image_moderation_azure_v1.sql`**. Client constants in `SpotSupabaseRepository` include **`pending_images`**.

## Details

### Buckets (from migration)

| Bucket id | Visibility | Purpose |
| --- | --- | --- |
| `pending_images` | Private | New uploads awaiting moderation |
| `approved_spot_images` | Private | Approved Spot imagery |
| `approved_profile_images` | Private | Approved profile photos |

### Spot media flow (summary)

1. Client uploads to **pending** path and creates/updates **`media_assets`** rows.
2. **Edge Function** `moderate-image` (per code comments) runs moderation.
3. On approval, assets move to **approved** buckets; Spot publish may use RPC **`publish_spot_with_approved_media_assets_v1`**.

### Profile photos

Same `media_assets` model with `kind = 'profile_image'` (see migration check constraint).

### Signed URLs

Feed and image views use signing paths from repository helpers—**TODO: verify** exact signing RPC or storage API used in `SpotSupabaseRepository` / `FeedRepository`.

### Failed publishes

Orphan pending objects and `media_assets` statuses (`failed`, `rejected`) should be handled per policy—**TODO: verify** cleanup jobs or client retry semantics.

## Related docs

- [image-moderation.md](image-moderation.md)
- [supabase.md](supabase.md)

## Open questions / TODOs

- Document retention policy for rejected pending files: TODO: verify in migrations or ops runbooks.
