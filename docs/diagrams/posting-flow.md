# Diagram: Posting and moderation

## Purpose

End-to-end create Spot through publish on the **Supabase** data plane.

## Audience

Engineering, safety.

## Current status

Matches `SpotPublishCoordinator`, `SpotSupabaseRepository`, and moderation migrations.

## Details

```mermaid
flowchart TD
  A[PostFlowViewModel submitPost] --> B[Build SpotPublishDraft]
  B --> C[SpotPublishCoordinator.enqueue]
  C --> D[Upload JPEGs to pending_images]
  D --> E[moderate-image Edge Function]
  E --> F{All assets approved?}
  F -->|No| G[Toast error / draft retained]
  F -->|Yes| H[publish_spot_with_approved_media_assets_v1 RPC]
  H --> I{RPC success?}
  I -->|No| J[Toast error]
  I -->|Yes| K[spotDidPostSuccess notification]
```

## Related docs

- [../product/posting-flow.md](../product/posting-flow.md)
- [../engineering/data-plane.md](../engineering/data-plane.md)
- [../engineering/image-moderation.md](../engineering/image-moderation.md)

## Open questions / TODOs

- None.
