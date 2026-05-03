# Diagram: Map spot drawer

## Purpose

State-style view of map selection and drawer.

## Audience

Engineering, QA.

## Current status

Target behavior for map UX; keep aligned with map tests.

## Details

```mermaid
stateDiagram-v2
  [*] --> MapIdle
  MapIdle --> SpotSelected: user taps pin
  SpotSelected --> DrawerOpen: open drawer
  DrawerOpen --> SpotSelected: user taps different pin / replace selected Spot
  DrawerOpen --> MapIdle: user dismisses drawer
  DrawerOpen --> MapIdle: user pans or zooms away
  DrawerOpen --> SpotDetail: user opens full Spot detail
  SpotDetail --> DrawerOpen: user returns to map
```

## Related docs

- [../product/map-experience.md](../product/map-experience.md)

## Open questions / TODOs

- Confirm “SpotDetail” transition naming vs actual navigation stack: TODO: verify in Map views.
