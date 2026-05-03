# Diagram: Onboarding

## Purpose

Visualize first-run onboarding relative to the main shell.

## Audience

Product and engineering.

## Current status

High-level; see `HomeTourManager` and `SpotFirstRunOnboardingManager` for exact steps.

## Details

```mermaid
flowchart TD
  A[Authenticated user enters app] --> B{First-run onboarding done?}
  B -->|No| C[SpotFirstRunOnboardingManager steps]
  C --> D[Complete or skip]
  B -->|Yes| E[Main tabs]
  D --> E
  E --> F{Home tour needed?}
  F -->|Yes| G[HomeTourManager coach]
  F -->|No| H[Normal home]
  G --> H
```

## Related docs

- [../product/onboarding.md](../product/onboarding.md)

## Open questions / TODOs

- Wire exact conditions to UI entry files: TODO: verify in `RootView`.
