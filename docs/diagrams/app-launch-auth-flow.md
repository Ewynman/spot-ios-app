# Diagram: App launch and authentication

## Purpose

Visualize cold start through session validation and main shell.

## Audience

Engineers, reviewers.

## Current status

Conceptual; align with `SpotApp`, `RootView`, and Supabase session APIs.

## Details

```mermaid
flowchart TD
  A[App launch] --> B[Load local session]
  B --> C{Session exists?}
  C -->|No| D[Show auth / welcome screen]
  C -->|Yes| E[Refresh or validate session]
  E --> F{Session valid?}
  F -->|No| D
  F -->|Yes| G[Load profile]
  G --> H{Profile exists?}
  H -->|No| I[Create or complete profile]
  H -->|Yes| J[Enter main app]
  I --> J
```

## Related docs

- [../engineering/networking-and-auth.md](../engineering/networking-and-auth.md)
- [../product/user-flows.md](../product/user-flows.md)

## Open questions / TODOs

- None.
