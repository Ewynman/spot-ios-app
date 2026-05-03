# Diagram: Universal Links

## Purpose

Sequence for opening Spot links.

## Audience

Engineering, support.

## Current status

Matches `DeepLinkRouter` + `DeepLinkState` behavior at a high level.

## Details

```mermaid
sequenceDiagram
  participant User
  participant iOS
  participant App
  participant Router
  participant Supabase

  User->>iOS: Tap Universal Link
  iOS->>App: Open via Associated Domains
  App->>Router: Pass incoming URL
  Router->>Router: Parse route
  Router->>App: Resolve auth requirements
  alt Auth required and missing
    App->>App: Save pending deep link
    App->>User: Show sign-in
  else Can continue
    App->>Supabase: Fetch linked resource
    Supabase-->>App: Resource or not found/private
    App->>User: Show target or fallback state
  end
```

## Related docs

- [../engineering/universal-links.md](../engineering/universal-links.md)

## Open questions / TODOs

- None.
