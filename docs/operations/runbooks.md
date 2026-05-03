# Runbooks

## Purpose

Short operational procedures for common checks.

## Audience

On-call engineers and release owners.

## Current status

High-level; expand with dashboard deep links as your org standardizes them.

## Details

### Verify Supabase health

- Open Supabase dashboard → project status, database health, Edge Function logs.
- Run a trivial authenticated query from SQL editor with a test user JWT if needed.

### Verify moderation function

- Supabase → Edge Functions → `moderate-image` (name **TODO: verify**) → logs and error rate.
- Submit a test image through staging app build.

### Verify Universal Links

- Device test: open `https://spotapp.online/s/{knownSpotId}`.
- Validate AASA with Apple’s CDN validator or `curl` **without** following redirects incorrectly.

### Verify App Store subscription

- App Store Connect → agreements, tax, banking.
- Sandbox purchase of product id **`spotPro`** (`SpotProProducts.swift`).

### Safety / moderation incident

- Triage user reports in your support tooling.
- If policy gap, coordinate content takedown via admin tools / DB procedures per [incident-response.md](incident-response.md).

## Related docs

- [../engineering/troubleshooting.md](../engineering/troubleshooting.md)
- [incident-response.md](incident-response.md)

## Open questions / TODOs

- Add org-specific links to dashboards: TODO: confirm with owner.
