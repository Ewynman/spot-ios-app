# Storage and media

## Purpose

Image pipeline buckets, upload flow, and signed URL usage for displaying media.

## Audience

Engineers working on posts, profiles, or moderation.

## Current status

Verified against the moderation migration, `SpotSupabaseRepository`, `FeedAPI`, `SpotImageGallery`, and `SupabaseUserService` on 2026-07-28.

## Details

### Buckets (from migration)

| Bucket id | Visibility | Purpose |
| --- | --- | --- |
| `pending_images` | Private | New uploads awaiting moderation |
| `approved_spot_images` | Private | Approved Spot imagery |
| `approved_profile_images` | Private | Approved profile photos. Signed for display when the object is the user's current avatar |
| `spots` | Private | Legacy Spot imagery and the bucket assumed by home-feed batch signing |
| `avatars` | Public | Legacy profile photos already stored as public URLs. New uploads do not write here |

### Spot media flow (summary)

1. Client inserts an owned **pending** `media_assets` row.
2. Client uploads bytes to the user's folder in `pending_images`.
3. Client invokes **`moderate-image`** with the media asset ID.
4. The Edge Function analyzes the image and, on approval, promotes it to `approved_spot_images`.
5. The client passes approved asset IDs to **`publish_spot_with_approved_media_assets_v1`**.

For Edit Spot, unchanged rows remain in place. Replacement bytes repeat steps
1–4, then `update_spot_editor_v1` atomically links approved replacements,
removes deleted relationships, applies `sort_index`, and refreshes the cover
layout metadata. Reorder-only edits do not upload or moderate bytes again.

Authenticated clients cannot directly insert, update, or delete `spot_images`.
Legacy authenticated write policies for the `spots` bucket are also removed;
new Spot media must use `pending_images` and the moderation-gated RPCs. Existing
legacy objects remain readable when attached to a visible Spot.

### Profile photos

New profile photos use pending upload, `moderate-image`, and `approved_profile_images`. `set_profile_image_from_approved_asset_v1` writes `users.profile_image_url` as `spot-storage://approved_profile_images/<path>` and sets `profile_image_asset_id`. Clients sign that path when rendering. Direct `UPDATE` of `profile_image_url` is revoked.

Legacy rows may still hold a public `avatars` URL. Those keep working until the photo is replaced. After a successful moderated upload the client best-effort deletes `avatars/{userId}/profile.jpg`.

### Signed URLs

- Repository, profile, map, Search, optimistic-publish, and lazy gallery paths read `spot_images.storage_bucket` and create seven-day signed URLs.
- Home-feed and map primary-image signing are bucket-aware: `get_home_feed_v1` / `get_map_spots_v1` return `primary_storage_bucket`, and `FeedAPI` groups `createSignedURLs` by that bucket (legacy default `spots`).

### Failed publishes

There is no repository-defined scheduled cleanup for pending, failed, rejected, or approved-but-unlinked assets. A partial multi-image failure can leave approved unlinked assets.

Account deletion performs best-effort client cleanup for `avatars` and `spots`; it does not enumerate `pending_images`, `approved_spot_images`, or `approved_profile_images`. The database RPC deletes `media_assets` rows, but Storage objects are not database rows and may remain.

## Related docs

- [image-moderation.md](image-moderation.md)
- [supabase.md](supabase.md)

## Open questions / TODOs

- Define and implement retention/garbage collection for unlinked media and all moderation statuses.
- Align Search signing with `spot_images.storage_bucket` the same way feed/map do.
- Extend account-deletion Storage cleanup to all owned buckets.
