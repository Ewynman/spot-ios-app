# Diagram: Supabase RLS

## Purpose

Decision flow for RLS enforcement.

## Audience

Security-minded engineers.

## Current status

General Supabase model.

## Details

```mermaid
flowchart TD
  A[Client request] --> B[Supabase receives JWT]
  B --> C[Identify auth.uid]
  C --> D[Apply table/storage RLS policy]
  D --> E{Policy allows?}
  E -->|Yes| F[Return data or allow mutation]
  E -->|No| G[Deny request]
  G --> H[Client shows safe error state]
```

## Related docs

- [../engineering/database-and-rls.md](../engineering/database-and-rls.md)

## Open questions / TODOs

- None.
