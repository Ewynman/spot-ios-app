# Spot Mock Data Seeder (Supabase)

Quickly create fake `users` and `spots` directly in Supabase (Postgres) for
dev / load testing.

## Prereqs

- Node 18+
- A Supabase project URL and the **service_role** key (from
  *Project Settings → API*). The publishable key won't work — it can't bypass RLS.

## Install

```bash
cd Mock
npm install
```

## Seed

Default = **500 users (50 private, 200 pro), 1–15 spots each, 1–3 images per
spot, locations sampled from ~60 cities across every populated continent**.

```bash
export SUPABASE_URL="https://<project-ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"

node seed.js
```

### Useful flags

| Flag | Default | Purpose |
| --- | --- | --- |
| `--users <n>` | `500` | Number of users to create in `public.users` |
| `--privateUsers <n>` | `50` | Random subset marked `is_private = true` |
| `--proUsers <n>` | `200` | Random subset marked `is_pro = true` |
| `--spotsMin <n>` `--spotsMax <n>` | `1` / `15` | Spots-per-user range |
| `--imagesMin <n>` `--imagesMax <n>` | `1` / `3` | Images-per-spot range |
| `--userIds <csv>` | — | Reuse existing users instead of creating new ones |
| `--skipUsers 1` | — | Skip user creation, just attach spots to existing users |
| `--dryRun 1` | — | Log a plan without writing |
| `--batchSize <n>` | `500` | Insert chunk size (rows per request) |

`is_private` and `is_pro` are independent random subsets, so a user may be both.

### What gets written

- `public.users`: id, username, email, profile_image_url, is_private, is_pro
- `public.spots`: user_id, vibe_tag_id, lat/lon (jittered around a city), location_name, likes_count, saves_count
- `public.spot_images`: 1–3 picsum.photos URLs per spot
- `public.vibe_tags`: 20 default vibe tags (only inserted if missing)

The seeder does **not** create `auth.users` — Spot's data plane has no FK to
`auth.users`, and avoiding the auth admin API removes rate-limit headaches and
makes the seed completely repeatable.

## Wipe

The DB part of a wipe is best done from the Supabase dashboard (SQL editor) or
via the project's MCP. A typical wipe (preserves all schema, RPCs, RLS, cron):

```sql
TRUNCATE
  public.feed_impressions,
  public.user_feed_events,
  public.user_creator_affinities,
  public.user_vibe_affinities,
  public.user_feed_profiles,
  public.user_hidden_spots,
  public.user_blocks,
  public.spot_likes,
  public.spot_bookmarks,
  public.bookmark_collection_spots,
  public.bookmark_collections,
  public.follows,
  public.follow_requests,
  public.spot_images,
  public.spots,
  public.users,
  public.vibe_tags
RESTART IDENTITY CASCADE;

DELETE FROM auth.identities;
DELETE FROM auth.sessions;
DELETE FROM auth.refresh_tokens;
DELETE FROM auth.mfa_factors;
DELETE FROM auth.mfa_challenges;
DELETE FROM auth.users;
```

Storage objects can't be deleted via SQL (Supabase blocks that with a guard
trigger). Use the helper script:

```bash
node wipe-storage.js
```

It clears the `avatars` and `spots` buckets via the supported Storage API.
