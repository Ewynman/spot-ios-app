# Legacy Firebase rules (archived)

**Status:** Deprecated — not used by the Spot iOS app on `main`.

Spot migrated the **application data plane** to **Supabase** (Postgres, Storage, Auth, RLS) in April 2026. These files are kept only as historical reference for the pre-migration Firebase stack.

## Do not use for new work

| Legacy artifact | Replaced by |
| --- | --- |
| `firestore.rules` | `supabase/migrations/*.sql` (RLS policies) |
| `firestoreStorage.rules` | Supabase Storage bucket policies in migrations |
| `SpotUploader` + Firestore callbacks | `SpotPublishCoordinator` + `SpotSupabaseRepository` |

## Allowed Firebase usage (current app)

Firebase SDKs remain for **analytics, crash reporting, and App Check only** (`AppDelegate`, `AnalyticsService`). They must **not** store users, spots, images, or social graph data.

See [docs/engineering/data-plane.md](../../docs/engineering/data-plane.md).
