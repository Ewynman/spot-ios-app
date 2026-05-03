# Diagram: Testing and release

## Purpose

Pipeline from code change to App Store.

## Audience

Engineers and release owners.

## Current status

Recommended team workflow.

## Details

```mermaid
flowchart TD
  A[Code/docs change] --> B[Run unit tests]
  B --> C[Run UI tests where applicable]
  C --> D[Run manual smoke tests]
  D --> E[Verify docs updated]
  E --> F[Verify security/RLS/moderation if touched]
  F --> G[TestFlight build]
  G --> H[App Store review checklist]
```

## Related docs

- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/release-process.md](../engineering/release-process.md)

## Open questions / TODOs

- None.
