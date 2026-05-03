# Diagram: Subscription / Pro

## Purpose

Paywall through entitlement.

## Audience

Product, engineering.

## Current status

Matches `SubscriptionManager` + StoreKit patterns.

## Details

```mermaid
flowchart TD
  A[User opens Pro entry point] --> B[Show paywall]
  B --> C[Load StoreKit products]
  C --> D{Product loaded?}
  D -->|No| E[Show retry/error state]
  D -->|Yes| F[Display localized price]
  F --> G[User purchases]
  G --> H{Purchase successful?}
  H -->|No| I[Show cancelled/error state]
  H -->|Yes| J[Update entitlement]
  J --> K[Unlock Pro features]
```

## Related docs

- [../product/pro-subscription.md](../product/pro-subscription.md)

## Open questions / TODOs

- None.
