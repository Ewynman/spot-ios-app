# Documentation maintenance

## Purpose

When and how to update Spot docs so they stay trustworthy.

## Audience

All contributors and Cursor agents.

## Current status

Team policy for this repository.

## Details

### When docs must be updated

- **New feature** shipped to users.
- **User flow** change (auth, onboarding, post, map, paywall).
- **Database schema** or RPC behavior change.
- **RLS** or storage policy change.
- **Data plane** change (must stay Supabase-only; update [data-plane.md](../engineering/data-plane.md) if allowlists change).
- **Subscription** behavior, product IDs, or paywall entry points change.
- **Universal Link** routes, domains, or AASA format change.
- **Environment variable** or Info.plist config keys change.
- **Release process** or CI scheme changes.

### PR checklist (docs)

- [ ] User-visible behavior change reflected in `docs/product/` if applicable.
- [ ] Engineering/security impact reflected in `docs/engineering/` or `docs/operations/`.
- [ ] Mermaid diagrams updated if the flow changed (`docs/diagrams/`).
- [ ] `docs/README.md` index updated if adding a new top-level page.
- [ ] Root `README.md` updated if quick start or schemes changed.
- [ ] No reintroduction of Firebase Firestore/Storage auth data plane (see [data-plane.md](../engineering/data-plane.md); `DataPlaneGuardTests` must pass).

### How to add diagrams

1. Add or edit a file under **`docs/diagrams/`** with a ```mermaid fenced block.
2. Link it from the relevant product or engineering page.

### Avoiding stale docs

- Prefer **linking** to code paths (`Spot/...`) over copying large blocks of code.
- Mark unknowns **`TODO: verify`** instead of inventing behavior.
- Remove deprecated flows when deleting code.

## Related docs

- [../README.md](../README.md)
- [../../README.md](../../README.md)

## Open questions / TODOs

- Optional: add CI markdown link check: TODO: verify if desired.
