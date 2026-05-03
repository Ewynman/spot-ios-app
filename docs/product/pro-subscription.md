# Pro subscription

## Purpose

Document Spot Pro: paywall entry points, StoreKit product ID, restore behavior, and gated features at a high level.

## Audience

Product, engineering, App Store review.

## Current status

StoreKit integration: `Spot/Services/SubscriptionManager.swift`, product IDs in `Spot/Utils/SpotProProducts.swift`. Subscription return deep link: `spotapp://subscription/return` handled in `DeepLinkRouter`.

## Details

### What Pro is

**Pro** is the paid subscription tier unlocking premium capabilities (exact feature list: **TODO: verify** in paywall copy and `ProEntitlementChecker` usage across features).

### Product ID (code)

| ID | Kind | Source |
| --- | --- | --- |
| `spotPro` | Yearly (primary product loaded first) | `SpotProProducts.yearly` |

**Pricing** is localized via StoreKit `Product.displayPrice`—not hardcoded. **App Store Connect** price tiers: **TODO: verify in App Store Connect**.

### Paywall entry points

Common entry points include Profile / Settings / “Go Pro” surfaces and feature gates—**TODO: verify** all `PaywallRouter` / paywall presentation call sites.

### Restore purchases

`SubscriptionManager` exposes restore flows (see `SubscriptionManager` for `isRestoring` and restore completion logs). User-facing copy lives in paywall views.

### Pro-gated features

Examples may include map filters or badges—**TODO: verify** by searching `hasPro`, `ProEntitlement`, or `SubscriptionManager` consumers.

### Subscription testing

- Use **Sandbox** Apple IDs and Xcode StoreKit testing configuration.
- **TODO: verify** StoreKit Configuration file presence in the Xcode project.

### Localized price

Built from `SubscriptionPriceLineFormatter` + `Product` subscription period.

## Related docs

- [../diagrams/subscription-flow.md](../diagrams/subscription-flow.md)
- [../engineering/release-process.md](../engineering/release-process.md)
- [../operations/app-store-review-notes.md](../operations/app-store-review-notes.md)

## Open questions / TODOs

- Complete feature gate inventory and screenshot list for review: TODO: verify with product.
