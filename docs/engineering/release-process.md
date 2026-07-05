# Release process

## Purpose

Pre-release, TestFlight, and App Store checklist at a high level.

## Audience

Release owners.

## Current status

Process expectations for iOS app + Supabase backend; exact team checklist may live in Notion—this doc is the repo anchor.

## Details

### Pre-release

- Ensure **GitHub Actions CI** passes on main (see [ci-cd.md](ci-cd.md)); verify **SpotTests** pass; run **SpotUITests** before major UI releases.
- Verify **RLS** and migrations applied to production Supabase in correct order.
- Verify **moderation** function live and secrets set.
- Verify **Universal Links** on device (see [universal-links.md](universal-links.md)).

### TestFlight

- Cut a `release/<version>` branch (e.g. `release/1.1.0`) and push it. The `testflight.yml` workflow derives `MARKETING_VERSION` from the branch name and uses the GitHub run number as the build number, then archives with the distribution cert and uploads to App Store Connect / TestFlight. See [ci-cd.md](ci-cd.md).
- To ship a new version, create a new `release/<version>` branch; pushes to the same branch keep the version and only bump the build number.
- The upload step requires the App Store Connect API secrets (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_BASE64`).
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
