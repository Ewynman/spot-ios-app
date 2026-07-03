## Changes
<!-- What changes and why it matters-->

## Testing
<!-- Add proof of functional testing, unit test, etc -->

## Checklist

### Code Quality & Testing (Required)
- [ ] Added Unit Tests For New Code (80% minimum coverage on changed files)
- [ ] All tests pass locally (`xcodebuild -scheme SpotTests test`)
- [ ] No breaking API changes (or documented if intentional)
- [ ] Confirmed no new warnings introduced
- [ ] Code follows existing patterns and style

### Documentation (Required)
- [ ] Updated docs (see `docs/operations/documentation-maintenance.md`)
- [ ] Updated relevant product docs if user-facing behavior changed
- [ ] Updated architecture/engineering docs if service/data layer changed
- [ ] Updated diagrams if flows changed significantly

### Data plane (required for auth, posting, storage, or `Spot/Services` changes)
- [ ] **No Firebase data plane** — no `FirebaseFirestore`, `FirebaseStorage`, `FirebaseAuth`, `SpotUploader`, or Firestore/Storage callbacks under `Spot/`
- [ ] Posting uses **`SpotPublishCoordinator`** / **`SpotSupabaseRepository`** (Supabase Storage + Postgres RPC)
- [ ] Schema/RLS changes include SQL under **`supabase/migrations/`**
- [ ] `SpotTests` **`DataPlaneGuardTests`** pass (`xcodebuild -scheme SpotTests test`)

See [docs/engineering/data-plane.md](docs/engineering/data-plane.md).

---

## Automated Validation

The following checks run automatically on every PR:

✅ **Code Coverage**: Enforces 80% minimum coverage on all changed production files  
✅ **API Stability**: Detects potential breaking changes to public APIs  
✅ **Documentation**: Validates documentation updates for significant changes  
✅ **Unit Tests**: All tests must pass before merge

See validation results in the PR checks above.
