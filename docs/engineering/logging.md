# Logging

## Purpose

Describe structured logging via `SpotLogger`, log levels, and debug categories.

## Audience

Engineers debugging features and writing new services.

## Current status

Implementation: `Spot/Utils/SpotLogger.swift`, `Spot/Utils/LoggingConfig.swift`, per-feature log enums under `Spot/Models/Logs/`.

## Details

### Pattern

1. Define an enum conforming to **`SpotLog`** (tag, level, message) for a component.
2. Emit with **`SpotLogger.log(_:details:)`** (and `info` / `error` helpers as appropriate).

### Levels

`LogLevel`: **debug**, **info**, **error** — with ordering for filtering.

### Debug categories

`DebugCategory` includes UI, navigation, feed, network, auth, image, location, performance, deepLink, moderation, privacy. Enable per category or use master switches / `UserDefaults` keys under `Constants.UserDefaultsKeys` (e.g. `logDeepLink`, `logAllDebugCategories`).

### Release behavior

`LoggingConfig` sets minimum level to **errors only** in non-DEBUG builds (see `#if DEBUG` branches).

### Map-only mode

`SpotLogger.mapOnlyLoggingEnabled` restricts noise during map debugging (see comments in `SpotLogger`).

## Related docs

- [architecture.md](architecture.md)
- [troubleshooting.md](troubleshooting.md)

## Open questions / TODOs

- None.
