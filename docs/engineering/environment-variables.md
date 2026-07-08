# Environment variables and config secrets

## Purpose

List configuration values the app and backend use, where they live, and whether they are secret.

## Audience

Engineers and infra owners.

## Current status

iOS client reads Supabase URL and anon key from **`Spot/Info.plist`** (see `Spot/Supabase/Supabase.swift`). Edge functions and Azure keys belong in **Supabase dashboard / function secrets**, not the app bundle.

## Details

| Name | Used by | Required | Secret? | Location | Notes |
| --- | --- | --- | --- | --- | --- |
| Supabase **project URL** (staging) | iOS app (DEBUG) | Yes | No (public URL) | `SupabaseEnvironment.swift` → `.staging.url` | Staging/development environment. |
| Supabase **anon / publishable key** (staging) | iOS app (DEBUG) | Yes | **Treat as sensitive** — must rely on **RLS** | `SupabaseEnvironment.swift` → `.staging.anonKey` | Never ship service-role in the app. |
| Supabase **project URL** (production) | iOS app (RELEASE) | Yes | No (public URL) | Injected by CI/CD from `SUPABASE_PRODUCTION_URL` secret | Production environment. |
| Supabase **anon / publishable key** (production) | iOS app (RELEASE) | Yes | **Treat as sensitive** — must rely on **RLS** | Injected by CI/CD from `SUPABASE_PRODUCTION_ANON_KEY` secret | Never ship service-role in the app. |
| `SUPABASE_STAGING_URL` | GitHub Actions (deploy.yml) | Optional | No | GitHub repository secrets | Staging project URL; falls back to hardcoded if not set. |
| `SUPABASE_STAGING_ANON_KEY` | GitHub Actions (deploy.yml) | Optional | Yes | GitHub repository secrets | Staging anon key; falls back to hardcoded if not set. |
| `SUPABASE_PRODUCTION_URL` | GitHub Actions (testflight.yml) | **Required** | No | GitHub repository secrets | Production project URL; TestFlight builds fail without this. |
| `SUPABASE_PRODUCTION_ANON_KEY` | GitHub Actions (testflight.yml) | **Required** | Yes | GitHub repository secrets | Production anon key; TestFlight builds fail without this. |
| `SUPABASE_SERVICE_ROLE_KEY` | Server / Edge only | If admin operations | **Yes** | Supabase secrets | **Never** in client. |
| `AZURE_CONTENT_SAFETY_*` | Moderation function | If Azure enabled | Endpoint: often non-secret; key: **Yes** | Function env in Supabase | Do not put in client. |
| Share / Universal Link config | iOS app | Yes | No | `Info.plist` → `SpotURLs` | Domains must match entitlements. |

### Example placeholders only

```xml
<!-- Do not copy real keys into docs or git history -->
<key>Supabase</key>
<dict>
  <key>url</key>
  <string>https://YOUR_PROJECT.supabase.co</string>
  <key>anonKey</key>
  <string>YOUR_ANON_OR_PUBLISHABLE_KEY</string>
</dict>
```

## Related docs

- [configuration.md](configuration.md)
- [supabase.md](supabase.md)
- [image-moderation.md](image-moderation.md)

## Open questions / TODOs

- Enumerate every Edge Function secret name from deployed functions: TODO: verify in Supabase dashboard.
