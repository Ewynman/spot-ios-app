# Spot Onboarding Tour Guide

This document explains how onboarding tours work in Spot at the product level (what users see, when they see it, and how completion is remembered).

---

## Overview

Spot currently has two onboarding experiences:

1. **Home First-Session Tour**
   - A lightweight intro shown to newly signed-up users on Home.
   - Includes a welcome sheet and a short guided coach flow.

2. **Post-Purchase Pro Tour**
   - A full-screen guided tour shown after a user becomes Pro.
   - Walks through key Pro features step-by-step.

Both tours are intentionally **one-time** by default and persisted locally with `UserDefaults`.

---

## 1) Home First-Session Tour

### User Experience

When conditions are met, the user sees:

1. **Welcome sheet** ("Welcome to Spot")
2. Tapping **Start Tour** opens a guided overlay
3. Overlay steps:
   - Profile (username)
   - Location
   - Vibe Tag
   - Like & Save
4. User can tap **Skip** at any point
5. On final step, **Done** completes the tour

### Trigger Conditions

The Home tour is eligible only when all are true:

- user is authenticated
- user appears to be in first session after signup (heuristic: no likes and no bookmarks yet)
- user has not previously completed the Home tour

### Persistence Behavior

- Primary key: `homeTourAccepted`
- Once completed/skipped, it will not show again.
- There is migration support from older per-user keys:
  - legacy key format: `hasSeenHomeTour.<userId or guest>`

### Notes

- Home onboarding is attached to Home screen lifecycle.
- The tour manager uses local state only; no server-side completion flag.
- Coach target frame plumbing exists (`CoachTarget`, frame preference key), but current Home coach overlay uses a demo-style overlay flow.

---

## 2) Post-Purchase Pro Tour

### User Experience

After becoming Pro, the user is shown a full-screen experience:

1. **Welcome step**
2. Feature walkthrough steps:
   - Five photos
   - Custom vibes
   - Edit spots
   - Bookmarks
   - Collections (2-substep sequence)
   - Search filters
   - Supporter badge
3. **Finale step** with CTA to continue using app

Controls include **Back**, **Skip**, and **Next**. Progress bar updates through steps.

### Trigger Conditions

The Pro tour appears when:

- Root receives a Pro-related trigger (for example post-purchase paths),
- and `PostPurchaseProOnboardingManager.shouldShow(userId:)` returns true.

`shouldShow` requires a non-empty user ID and absence of seen-flag.

### Persistence Behavior

- Per-user key format:
  - `hasSeenPostPurchaseProOnboarding.<userId>`
- Completion path:
  - final CTA marks seen
- Skip path:
  - skip also marks seen

Result: user sees this Pro onboarding only once per account on that device unless reset.

---

## Where Tour State Is Managed

- **Home tour state**
  - `HomeTourManager`
- **Pro tour state**
  - `PostPurchaseProOnboardingManager`
- **Presentation orchestration**
  - Root/Home screens host the entry points and presentation wrappers.

---

## Resetting Tours (QA / Demo)

Tours are `UserDefaults`-backed, so clearing relevant keys resets visibility.

### Keys to clear

- Home tour:
  - `homeTourAccepted`
  - (optional legacy cleanup) `hasSeenHomeTour.<userId>`
- Pro tour:
  - `hasSeenPostPurchaseProOnboarding.<userId>`

You can also reset by deleting app data/uninstalling for local testing.

---

## Product Intent

- **Home tour**: teach first-time users the meaning of core feed UI.
- **Pro tour**: reinforce subscription value immediately after upgrade.
- **Skip-first UX**: users can always skip to reduce friction.
- **One-time memory**: avoid repetitive onboarding fatigue.

---

## Recommended Future Enhancements

1. Add explicit "Replay tour" action in Settings.
2. Track analytics events for:
   - shown
   - started
   - completed
   - skipped
   - step drop-off
3. Consider server-side tour state sync for multi-device consistency.
4. Add A/B variants for welcome copy and Pro step ordering.

