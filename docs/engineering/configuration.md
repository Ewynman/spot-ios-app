# Configuration

## Purpose

Where non-code configuration lives: Info.plist, entitlements, URL schemes, Associated Domains.

## Audience

Engineers setting up local builds and release signing.

## Current status

Verified file paths: `Spot/Info.plist`, `Spot/Spot.entitlements`.

## Details

### Info.plist

| Key area | Purpose |
| --- | --- |
| `CFBundleURLTypes` | Custom URL scheme **`spotapp`** for deep links. |
| `SpotURLs` | `shareURLBase`, `universalLinkDomains`, `customScheme` read by `URLConfiguration`. |
| `Supabase` | `url` and `anonKey` for `SupabaseClient` initialization. |
| Usage descriptions | Notifications, photos, camera, location as required by Apple. |

### Entitlements (`Spot/Spot.entitlements`)

- **Sign in with Apple** — `com.apple.developer.applesignin`
- **Associated Domains** — `applinks:spotapp.online`, `applinks:www.spotapp.online`

### Universal Links vs DEBUG

`Info.plist` may list extra hosts (e.g. `localhost`, ngrok-style hosts) for development; **`DeepLinkRouter`** allows `https` only when `URLConfiguration.isAllowedUniversalLinkHost` returns true. `http://localhost` is also accepted in router for local testing.

### Logging defaults

`Config/LoggingDefaults.plist` (bundled) seeds `LoggingConfig` / `UserDefaults` toggles—see [logging.md](logging.md).

## Related docs

- [universal-links.md](universal-links.md)
- [environment-variables.md](environment-variables.md)

## Open questions / TODOs

- Document any xcconfig files if introduced for multi-environment builds: TODO: verify.
