# App Store review notes

## Purpose

Information reviewers need for subscriptions, safety, and deep links.

## Audience

App Store review, internal release.

## Current status

Verify all **TODO** items before each submission.

## Details

### Where subscription is presented

**TODO: verify** all entry points; typically Profile → Settings → Pro / paywall surfaces.

### Product ID (code)

- **`spotPro`** — yearly product in `Spot/Utils/SpotProProducts.swift`.

**App Store Connect pricing / metadata:** TODO: verify in App Store Connect.

### Demo credentials

**TODO: verify** whether Apple demo account is required for your review flow.

### Universal Links

Spot detail links use `https://spotapp.online/s/{spotId}` (and `www` variant). See [../engineering/universal-links.md](../engineering/universal-links.md).

### Moderation / safety

Images for Spots and profile photos are processed through server-side moderation (`media_assets` / Azure Content Safety per migrations). Rejected uploads receive in-app messaging without graphic detail.

### Privacy / support links

**TODO: verify** URLs shown in App Store Connect match live privacy policy and support pages.

## Related docs

- [../product/pro-subscription.md](../product/pro-subscription.md)
- [../product/support-and-policies.md](../product/support-and-policies.md)

## Open questions / TODOs

- Fill in concrete review notes text file export if Apple asks for field-by-field copy: TODO: verify with owner.
