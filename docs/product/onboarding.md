# Onboarding

## Purpose

Explain first-run onboarding: what it teaches, where it starts, and how it differs from other tours.

## Audience

Product, UX, engineering, support.

## Current status

Based on `Spot/Managers/HomeTourManager.swift` (`HomeTourManager`, `SpotFirstRunOnboardingManager`).

## Details

### Why onboarding exists

Onboarding orients new users to **what a Spot is**, **vibe tags**, **likes/bookmarks/follows**, **map discovery**, and **posting**—without blocking returning users.

### Entry points and behavior

1. **`HomeTourManager`** — Short tour after first session post-signup when `startIfNeeded(isFirstSessionAfterSignup:)` is true and `homeTourAccepted` is false in `UserDefaults`. Steps: username, location, vibe, like/save coach (`HomeTourManager.Step`).
2. **`SpotFirstRunOnboardingManager`** — Longer multi-step coach (`SpotFirstRunOnboardingManager.Step`: welcome, spot card, details, vibe, like, bookmark, creator, map tab, user location, markers, marker preview, finale). Completion/skips tracked under `spotFirstRunOnboarding.*` keys in `UserDefaults`.

### What onboarding teaches

- **Spot** as the core content unit (card and details).
- **Vibe tags** as discovery language.
- **Like / bookmark** for taste and saving.
- **Follow** creators.
- **Map tab**, **user location**, **markers**, **marker preview** → bridge into map discovery.

### Pro tour

The codebase includes flows for **Pro** (paywall, StoreKit). **Do not change the existing Pro purchase / tour UX** unless a task explicitly asks for it—per team rule preserved in `.cursor/rules/project.mdc`.

### Distinction: “normal” onboarding vs Pro

- **Normal onboarding** — `HomeTourManager` / `SpotFirstRunOnboardingManager` for core app literacy.
- **Pro** — Subscription paywall and entitlements; separate from first-run coach content.

## Related docs

- [user-flows.md](user-flows.md)
- [map-experience.md](map-experience.md)
- [../engineering/architecture.md](../engineering/architecture.md)

## Open questions / TODOs

- Exact UI triggers wiring `startIfNeeded` from which screen: TODO: verify in `RootView` / tab shell.
