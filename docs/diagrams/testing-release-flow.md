# Diagram: Testing and release

## Purpose

Pipeline from code change to App Store.

## Audience

Engineers and release owners.

## Current status

Recommended team workflow using GitHub Actions CI/CD. Xcode Cloud is disabled.

## Details

```mermaid
flowchart TD
  A[Code/docs change] --> B[Create PR]
  B --> C[GitHub Actions CI runs]
  C --> D[SpotTests unit tests]
  D --> E{Tests pass?}
  E -->|No| F[Fix issues and push]
  F --> C
  E -->|Yes| G[Code review]
  G --> H[Merge to main]
  H --> I[CI runs on main]
  I --> J[Run SpotUITests if major UI changes]
  J --> K[Run manual smoke tests]
  K --> L[Verify docs updated]
  L --> M[Verify security/RLS/moderation if touched]
  M --> N[TestFlight build]
  N --> O[App Store review checklist]
```

## Related docs

- [../engineering/ci-cd.md](../engineering/ci-cd.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/release-process.md](../engineering/release-process.md)

## Open questions / TODOs

- None.
