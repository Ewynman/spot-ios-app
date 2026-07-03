# Diagram: Testing and release

## Purpose

Pipeline from code change to App Store.

## Audience

Engineers and release owners.

## Current status

Recommended team workflow using custom CI/CD pipeline. Xcode Cloud is disabled.

## Details

```mermaid
flowchart TD
  A[Code/docs change] --> B[Create PR]
  B --> C[CI/CD pipeline runs]
  C --> D[Unit tests SpotTests]
  D --> E[UI tests where applicable]
  E --> F{Tests pass?}
  F -->|No| G[Fix issues]
  G --> A
  F -->|Yes| H[Code review]
  H --> I[Merge to main]
  I --> J[Run manual smoke tests]
  J --> K[Verify docs updated]
  K --> L[Verify security/RLS/moderation if touched]
  L --> M[TestFlight build]
  M --> N[App Store review checklist]
```

## Related docs

- [../engineering/ci-cd.md](../engineering/ci-cd.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/release-process.md](../engineering/release-process.md)

## Open questions / TODOs

- None.
