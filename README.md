# Spot

## Overview

**Spot** is a SwiftUI iOS app for social **place discovery**: users share and browse **Spots** (saved place recommendations with photos, location, and **vibe tags**). The stack centers on **Supabase** (Auth, Postgres, Storage) with **Firebase** used for analytics, crash reporting, and App Check. See **[docs/README.md](docs/README.md)** for the full documentation index.

## Quick start

1. Clone the repository and open **`Spot.xcodeproj`** in Xcode.
2. Configure **`Spot/Info.plist`** → `Supabase` with your project **`url`** and **`anonKey`** from the [Supabase dashboard](https://supabase.com/dashboard) (never commit real keys to a public fork).
3. Select the **Spot** scheme and an **iPhone Simulator** (or device), then Run (**⌘R**).

## Repository structure

| Path | Contents |
| --- | --- |
| `Spot/` | iOS app sources (Views, ViewModels, Services, Models, Utils) |
| `SpotTests/` | Swift Testing unit tests |
| `SpotUITests/` | XCTest UI tests |
| `supabase/migrations/` | Postgres / RLS / storage / moderation SQL |
| `docs/` | Product, engineering, diagram, and operations documentation |
| `Spot.xcodeproj` | Xcode project |
| `Spot.xctestplan` / `SpotUITests.xctestplan` | Test plans |

## Requirements

- **macOS** with **Xcode** (recent release recommended; minimum version: TODO: verify team standard).
- **Apple Developer** account for device testing, Sign in with Apple, push, and Associated Domains as used by the app.
- **Supabase** project access for backend configuration.

iOS deployment targets vary by target in the project (e.g. **17.0** / **18.5** in `project.pbxproj`); use Xcode to confirm the app target.

## Configuration

- **Supabase** — `Spot/Info.plist` under the `Supabase` dictionary (`url`, `anonKey`). Loaded in `Spot/Supabase/Supabase.swift`.
- **Share / Universal Links** — `Spot/Info.plist` → `SpotURLs` (`shareURLBase`, `universalLinkDomains`, `customScheme`); see [docs/engineering/configuration.md](docs/engineering/configuration.md).
- **Entitlements** — `Spot/Spot.entitlements` (Associated Domains, Sign in with Apple).

Do not add **service role** keys, Azure secrets, or other server-only credentials to the app bundle or docs.

## Running the app

1. Open **`Spot.xcodeproj`**.
2. Scheme: **Spot**.
3. Choose a simulator or a signed development device, then Run.

## Testing

| Goal | Scheme / command |
| --- | --- |
| Unit tests only | **SpotTests** |
| UI tests only | **SpotUITests** |
| Default combined plan | **Spot** scheme Test action (`Spot.xctestplan`) |

Example (simulator UDID):

```sh
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
BEAUTIFY=$(command -v xcbeautify >/dev/null && echo "xcbeautify" || echo "cat")
xcodebuild -scheme SpotTests -destination "id=$SIM_ID" test | $BEAUTIFY
```

See [docs/engineering/testing.md](docs/engineering/testing.md) for philosophy and layout.

## Documentation

- **Index:** [docs/README.md](docs/README.md) — product, engineering, diagrams, operations, and suggested reading paths.
- **Architecture:** [docs/engineering/architecture.md](docs/engineering/architecture.md)
- **Local setup:** [docs/engineering/local-setup.md](docs/engineering/local-setup.md)
- **RLS / security:** [docs/engineering/database-and-rls.md](docs/engineering/database-and-rls.md), [docs/engineering/data-plane.md](docs/engineering/data-plane.md), [docs/engineering/networking-and-auth.md](docs/engineering/networking-and-auth.md)

## Security and safety

Authentication and **Row Level Security (RLS)** on Supabase are authoritative for data access. **Image moderation** is required for Spot and profile media. The app **does not** use Firebase Firestore or Firebase Storage for user or spot data ([docs/engineering/data-plane.md](docs/engineering/data-plane.md)). See [docs/engineering/image-moderation.md](docs/engineering/image-moderation.md). Operational response: [docs/operations/incident-response.md](docs/operations/incident-response.md).

## Universal Links

Spot share and open-in-app links are documented in **[docs/engineering/universal-links.md](docs/engineering/universal-links.md)** (paths, entitlements, AASA, testing).

## Release

High-level checklists: [docs/engineering/release-process.md](docs/engineering/release-process.md) and [docs/operations/runbooks.md](docs/operations/runbooks.md).

## Support

User-facing support and policy links: see [docs/product/support-and-policies.md](docs/product/support-and-policies.md) and in-app Settings (TODO: verify exact URLs in code).
