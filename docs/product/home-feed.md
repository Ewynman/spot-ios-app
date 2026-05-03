# Home feed

## Purpose

Describe the home feed’s role, how content is loaded, and privacy expectations.

## Audience

Product, engineering.

## Current status

Primary implementation: `Spot/Services/Feed/FeedRepository.swift` using Supabase RPC **`get_home_feed_v1`** (and status RPC **`get_home_feed_status_v1`** per comments in repository). On-device `FeedRanker` exists for tests/experiments.

## Details

### Purpose

The **home feed** is the default discovery surface after launch: a ranked, paginated list of Spots tailored to the viewer.

### Ranking behavior

- **Server-side candidate set and ranking** via `get_home_feed_v1` (authoritative for production feed).
- **Client** signs primary images for display and manages `FeedLoadState` (initial load, load more, empty reasons, errors, refresh toasts).
- **`FeedRanker`** — on-device scoring documented in tests / non-RPC experiments; not the sole source of truth for shipped feed unless product changes that.

### Signals (may influence ranking)

Exact weighting is **server-defined** in Postgres/RPC. Likely inputs include creator relationship, vibes, recency, location, and user actions—**TODO: verify** in SQL migration or function definition for `get_home_feed_v1`.

Plausible client/server inputs to keep in mind:

- Creator identity and follow graph
- Vibe tags
- Location / distance
- Likes, bookmarks, follows
- Impressions / dedupe (`feed_impressions` mentioned in `FeedRepository`)

### Privacy and safety

- Private authors and blocks must be enforced **with RLS and server queries**; client filters are additive only.
- `AuthorPrivacyCache` supports client-side filtering and caching—must not replace server enforcement.

### Empty / error / loading

`FeedLoadState` distinguishes idle, loading initial/more, loaded, empty (with reason), and error while retaining prior items when possible.

## Related docs

- [../engineering/architecture.md](../engineering/architecture.md)
- [../engineering/networking-and-auth.md](../engineering/networking-and-auth.md)
- [profiles-and-social.md](profiles-and-social.md)

## Open questions / TODOs

- Document exact RPC parameters and scoring once reviewed in Supabase SQL: TODO: verify in database repo / migrations.
