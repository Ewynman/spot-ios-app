# Incident response

## Purpose

Severity model, example incidents, immediate actions, and documentation expectations.

## Audience

Engineering leadership and on-call.

## Current status

Template aligned with Spot risk areas (auth, RLS, moderation, links, subscriptions).

## Details

### Severity levels (suggested)

| Level | Meaning |
| --- | --- |
| **SEV1** | Active data exposure, auth bypass, or widespread outage |
| **SEV2** | Partial outage or elevated error rate with user impact |
| **SEV3** | Limited bug or degraded non-critical feature |

### Example incidents

- Suspected **auth bypass** or token mishandling.
- **RLS** misconfiguration exposing private rows.
- **Image moderation** outage causing publish failures or unmoderated paths.
- **Universal Links** broken after website or entitlement change.
- **Subscription** purchase or restore systemic failure.
- **Major crash** spike from a release.

### Immediate steps

1. **Contain** — disable affected feature flag if any; revert bad migration only with a forward-safe plan.
2. **Assess user safety** — for content/RLS issues, prioritize stopping leakage (revoke policies / take service offline only if justified).
3. **Communicate** — internal status + user messaging if user-visible.
4. **Log preservation** — export Supabase logs and app analytics for the window.

### Rollback / disable options

- iOS: phased release halt, previous build promotion.
- Backend: roll forward with corrective SQL; avoid destructive rollback of migrations without review.

### Post-incident

- Root cause document, action items, and **update** [database-and-rls.md](../engineering/database-and-rls.md), [universal-links.md](../engineering/universal-links.md), or [image-moderation.md](../engineering/image-moderation.md) if behavior changed.

## Related docs

- [runbooks.md](runbooks.md)
- [documentation-maintenance.md](documentation-maintenance.md)

## Open questions / TODOs

- Align severity names with company incident policy: TODO: confirm with owner.
