# Diagram: Image moderation sequence

## Purpose

Sequence for moderation-gated uploads.

## Audience

Engineering, safety.

## Current status

Architectural; matches [../engineering/image-moderation.md](../engineering/image-moderation.md).

## Details

```mermaid
sequenceDiagram
  participant User
  participant App
  participant Function as Moderation Function
  participant Azure as Azure Content Safety
  participant Storage as Supabase Storage
  participant DB as Supabase DB

  User->>App: Selects image
  App->>Function: Submit image for moderation
  Function->>Azure: Analyze image
  Azure-->>Function: Category severities
  Function-->>App: Approved or blocked
  alt Blocked
    App->>User: Show safe rejection message
  else Approved
    App->>Storage: Upload / promote media
    App->>DB: Save via RPC
  end
```

## Related docs

- [../engineering/image-moderation.md](../engineering/image-moderation.md)

## Open questions / TODOs

- None.
