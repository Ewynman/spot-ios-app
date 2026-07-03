# Release process

## Purpose

Pre-release, TestFlight, and App Store checklist at a high level.

## Audience

Release owners.

## Current status

Process expectations for iOS app + Supabase backend; exact team checklist may live in Notion—this doc is the repo anchor.

## Details

### Pre-release

- Ensure **CI/CD pipeline** passes (see [ci-cd.md](ci-cd.md)); run **SpotTests** on CI or locally; run **SpotUITests** before major UI releases.
- Verify **RLS** and migrations applied to production Supabase in correct order.
- Verify **moderation** function live and secrets set.
- Verify **Universal Links** on device (see [universal-links.md](universal-links.md)).

### TestFlight

- Increment build number, archive with distribution cert.
- Smoke: auth, feed, map drawer, post happy path, deep link, Pro purchase in sandbox.

### App Store

- Update screenshots/metadata as needed.
- Subscription review notes: see [../operations/app-store-review-notes.md](../operations/app-store-review-notes.md).

### Rollback / incidents

If a bad build ships, use App Store phased release controls and/or expedited rollback; for backend, apply forward-fix migrations—see [../operations/incident-response.md](../operations/incident-response.md).

## Related docs

- [ci-cd.md](ci-cd.md)
- [troubleshooting.md](troubleshooting.md)
- [../operations/runbooks.md](../operations/runbooks.md)

## Open questions / TODOs

- Attach internal release checklist link if not secret: TODO: confirm with owner.
