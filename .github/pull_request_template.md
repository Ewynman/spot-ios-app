## Changes
<!-- What changes and why it matters-->

## Testing
<!-- Add proof of functional testing, unit test, etc -->

## Checklist
- [ ] Added Unit Tests For New Code
- [ ] Confirmed no new warnings introduced
- [ ] Updated docs (see `docs/operations/documentation-maintenance.md`)

### Data plane (required for auth, posting, storage, or `Spot/Services` changes)
- [ ] **No Firebase data plane** — no `FirebaseFirestore`, `FirebaseStorage`, `FirebaseAuth`, `SpotUploader`, or Firestore/Storage callbacks under `Spot/`
- [ ] Posting uses **`SpotPublishCoordinator`** / **`SpotSupabaseRepository`** (Supabase Storage + Postgres RPC)
- [ ] Schema/RLS changes include SQL under **`supabase/migrations/`**
- [ ] `SpotTests` **`DataPlaneGuardTests`** pass (`xcodebuild -scheme SpotTests test`)

See [docs/engineering/data-plane.md](docs/engineering/data-plane.md).
