# Troubleshooting

## Purpose

Common failures when building, running, or testing Spot.

## Audience

All engineers.

## Current status

Living doc—extend as new failure modes appear.

## Details

| Symptom | Things to check |
| --- | --- |
| **Build fails** | Xcode version, Swift package resolve, signing team, deployment target. |
| **Missing config** | `Info.plist` `Supabase.url` / `anonKey` and `SpotURLs` present for the configuration you run. |
| **Supabase auth / session** | Clock skew, key mismatch, user banned; logs in `SpotLogger` auth category. |
| **RLS permission denied** | JWT present? Policy matches `auth.uid()`? Migration applied? |
| **Image upload fails** | Bucket policy, file size/MIME limits in migration, network. |
| **Moderation function fails** | Azure secrets, function logs in Supabase dashboard. |
| **Universal Links open Safari** | AASA, entitlements, host spelling, device vs simulator. |
| **StoreKit products empty** | Product ID `spotPro`, agreements in App Store Connect, sandbox user. |
| **Map markers missing** | Location permission, map RPC errors, `SpotLogger` map-only mode filtering logs. |
| **Tests pass locally but fail CI** | Simulator OS version, destination name, flaky UI timing—pin destinations. |

## Related docs

- [local-setup.md](local-setup.md)
- [universal-links.md](universal-links.md)
- [../operations/runbooks.md](../operations/runbooks.md)

## Open questions / TODOs

- Add links to Supabase dashboard sections once standardized: TODO: verify.
