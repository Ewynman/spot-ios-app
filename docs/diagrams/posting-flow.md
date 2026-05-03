# Diagram: Posting and moderation

## Purpose

End-to-end create Spot through publish.

## Audience

Engineering, safety.

## Current status

Matches product posting doc and Supabase moderation pipeline.

## Details

```mermaid
flowchart TD
  A[Create Spot] --> B[Select images]
  B --> C[Enter Spot details]
  C --> D[Tap publish]
  D --> E{Authenticated?}
  E -->|No| F[Show auth required]
  E -->|Yes| G[Moderate all images]
  G --> H{All approved?}
  H -->|No| I[Block publish and show safe reason]
  H -->|Yes| J[Upload images]
  J --> K[Insert Spot record]
  K --> L{Insert succeeds?}
  L -->|No| M[Show error and preserve draft]
  L -->|Yes| N[Show published Spot]
```

## Related docs

- [../product/posting-flow.md](../product/posting-flow.md)
- [../engineering/image-moderation.md](../engineering/image-moderation.md)

## Open questions / TODOs

- None.
