# CI/CD Pipeline

## Purpose

Documents the continuous integration and continuous deployment pipeline for the Spot iOS app.

## Audience

Developers, release owners, and anyone maintaining or troubleshooting the build pipeline.

## Current status

**GitHub Actions** is the active CI/CD system. **Xcode Cloud is disabled** to avoid redundant builds and maintain a single source of truth.

## Details

### CI/CD System: GitHub Actions

The Spot project uses GitHub Actions for continuous integration and deployment. Configuration lives in `.github/workflows/`.

#### Workflows

1. **`ci.yml`** - Pull Request validation (runs on PRs to main)
2. **`deploy.yml`** - Firebase App Distribution deployment (runs on merge to main)

#### Main workflow: `ci.yml`

**Triggers:**
- Pull requests to `main`
- Pushes to `main`

**Environment:**
- Runner: macOS 15
- Xcode: Default Xcode on the runner (must support the available simulator runtimes)
- Simulator: iPhone 16 simulator

**Pipeline stages:**

1. **Checkout:** Pull repository code with full history (for diff comparison)
2. **Setup:** Install xcbeautify and jq (for JSON parsing)
3. **Cache:** Restore Swift Package Manager dependencies
4. **API Validation (PR only):** Check for breaking API changes
5. **Documentation Validation (PR only):** Validate documentation updates
6. **Test:** Run SpotTests scheme with code coverage enabled
7. **Coverage Validation (PR only):** Enforce 80% coverage on changed files
8. **Artifacts:** Upload test results (`.xcresult`) and coverage reports
9. **Summary:** Generate coverage summary in GitHub
10. **PR Comment:** Post validation results as PR comment

**What it validates:**
- All unit tests pass
- No compilation errors
- Code coverage is collected and meets 80% threshold on changed files
- No breaking API changes (or they're documented)
- Documentation updates for significant changes
- Data plane compliance (via DataPlaneGuardTests)

See `.github/workflows/README.md` for detailed workflow documentation.

---

#### Deployment workflow: `deploy.yml`

**Triggers:**
- Merge to `main` (after PR validation passes)
- Manual workflow dispatch

**Environment:**
- Runner: macOS 15
- Xcode: Default Xcode on the runner
- Requires: Apple signing certificates and Firebase credentials

**Pipeline stages:**

1. **Checkout:** Pull repository code with full history
2. **Version Management:** Auto-increment build number
3. **Release Notes:** Extract PR information for release notes
4. **Firebase Configuration:** Inject GoogleService-Info.plist from secrets
5. **Code Signing:** Install certificates and provisioning profiles
6. **Build:** Archive and export signed IPA
7. **Deploy:** Upload to Firebase App Distribution
8. **Version Commit:** Push build number update back to main

**What it does:**
- Automatically increments `CURRENT_PROJECT_VERSION` in Xcode project via `scripts/increment-build-number.sh`
- **Pushes the build number bump to `main` before building** (prevents duplicate Firebase build numbers when upload succeeds but a later step fails)
- Builds signed IPA for distribution
- Generates release notes from merged PR title and description
- Uploads to Firebase App Distribution with testers group
- Skips re-deploy on bump commits (`Bump build number to … [skip ci]`)

**Required secrets:**
- `GOOGLE_SERVICE_INFO_PLIST_BASE64` - Firebase GoogleService-Info.plist file (base64 encoded)
- `FIREBASE_APP_ID` - Firebase iOS App ID
- `FIREBASE_SERVICE_ACCOUNT_JSON` - Firebase service account credentials
- `APPLE_CERTIFICATE_BASE64` - Distribution certificate (.p12 encoded)
- `APPLE_CERTIFICATE_PASSWORD` - Certificate password
- `PROVISIONING_PROFILE_BASE64` - Provisioning profile encoded
- `KEYCHAIN_PASSWORD` - Temporary keychain password

See [firebase-distribution-setup.md](firebase-distribution-setup.md) for detailed setup instructions.

---

### Xcode Cloud Status

**Xcode Cloud is intentionally disabled** for this repository.

#### Why disabled

- **Single source of truth:** GitHub Actions is the sole CI/CD system
- **Cost management:** Avoids consuming Apple build minutes unnecessarily
- **Consistency:** All builds use the same GitHub Actions configuration
- **Transparency:** CI logs and results are visible in GitHub PR checks
- **Control:** Better control over build triggers, caching, and artifacts

#### How it's disabled

1. **App Distribution:** Workflows disabled in App Store Connect → App Distribution
2. **No workflow files:** Repository contains no `.xcode/` workflow directory
3. **Marker file:** `.xcode-cloud-disabled` at repository root documents this decision

#### Keeping it disabled

Xcode Cloud configuration is managed through App Store Connect. To keep it disabled:

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to your app → **App Distribution** → **Xcode Cloud**
3. Ensure all workflows are **disabled** or **deleted**
4. Do not enable "Start Conditions" for:
   - Branch Changes
   - Pull Requests
   - Tag Changes

If Xcode Cloud starts building unexpectedly, check these settings immediately.

### Local vs CI Builds

#### Running tests locally

Developers can run the same tests that CI runs:

```bash
# Get first available iPhone simulator
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')

# Run unit tests (matches CI)
xcodebuild \
  -scheme SpotTests \
  -destination "id=$SIM_ID" \
  -enableCodeCoverage YES \
  test | xcbeautify
```

Or use the convenience variable from project rules:

```bash
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
BEAUTIFY=$(command -v xcbeautify >/dev/null && echo "xcbeautify" || echo "cat")

xcodebuild -scheme SpotTests -destination "id=$SIM_ID" test | $BEAUTIFY
```

#### CI environment details

- **Xcode version:** Default Xcode on the macos-15 runner
- **Swift version:** Provided by the default Xcode on the runner
- **Simulator:** iPhone 16 (`platform=iOS Simulator,name=iPhone 16`)
- **Caching:** Swift Package Manager dependencies cached between runs
- **Code coverage:** Always enabled (`-enableCodeCoverage YES`)

### Test Coverage

CI collects code coverage data on every run and **enforces coverage requirements** on pull requests.

**Coverage Requirements:**
- **80% minimum coverage** on all changed production Swift files
- Measured using `xcrun xccov` against `.xcresult` bundles
- Only applies to files under `Spot/` (excludes test files)
- Validation runs automatically on every PR

**How it works:**
1. Tests run with `-enableCodeCoverage YES`
2. Coverage data extracted with `xcrun xccov`
3. Changed files identified via `git diff`
4. Coverage calculated per changed file
5. PR fails if any changed file < 80% coverage

**Coverage validation script:**
- Location: `scripts/validate-coverage.sh`
- Usage: `./scripts/validate-coverage.sh <xcresult-path> <base-branch> <coverage-threshold>`
- Can be run locally before pushing

**Coverage reports:**
- Uploaded as artifacts (retained for 7 days)
- Summary posted to PR as comment
- Full report available in GitHub Actions logs

**Exemptions:**
- Files with no executable lines (e.g., pure data models)
- Files not in production code path
- Can be discussed with team if threshold is impractical for specific cases

### Artifacts

The CI workflow uploads artifacts that are retained for 7 days:

1. **Test results** (`test-results`): `.xcresult` bundles from test runs
   - Can be opened in Xcode for detailed failure analysis
   - Includes all test logs, screenshots, and performance metrics

2. **Coverage reports** (`coverage-reports`): Raw coverage data from ProfileData
   - Can be processed with `xcrun xccov` for analysis
   - Used for future coverage reporting integrations

### Pull Request Checks

When a PR is opened or updated, GitHub Actions automatically:

1. **Validates API stability:** Detects potential breaking changes to public APIs
2. **Validates documentation:** Checks if docs need updates based on code changes
3. **Runs the full unit test suite:** All tests must pass
4. **Validates code coverage:** Enforces 80% minimum on changed files
5. **Reports status:** Shows results as checks on the PR
6. **Posts comment:** Summarizes validation results in PR comment
7. **Blocks merge:** If any check fails (when required checks are configured)

**Validation checks (PR only):**

#### 1. API Breaking Change Detection
- **Script:** `scripts/validate-api-changes.sh`
- **Purpose:** Detects changes to public Swift APIs that might break compatibility
- **What it checks:**
  - Removed public functions, classes, structs, enums, protocols
  - Changed function signatures
  - Modified public properties
- **Result:** Warning if breaking changes detected (doesn't block PR, but requires acknowledgment)

#### 2. Documentation Validation
- **Script:** `scripts/validate-documentation.sh`
- **Purpose:** Ensures documentation stays in sync with code changes
- **What it checks:**
  - Service/repository changes → architecture docs
  - ViewModel changes → product docs
  - Database migrations → database-and-rls.md
  - Auth changes → networking-and-auth.md
  - Config changes → configuration.md
- **Result:** Warning with suggestions if docs may need updates

#### 3. Code Coverage Enforcement
- **Script:** `scripts/validate-coverage.sh`
- **Purpose:** Ensures all new/changed code is properly tested
- **What it checks:**
  - Extracts coverage for each changed production Swift file
  - Calculates line coverage percentage
  - Compares against 80% threshold
- **Result:** Fails PR if any changed file below threshold

Developers and reviewers can click on the check to see detailed logs and artifacts.

### Troubleshooting

#### Pipeline failures

If the CI/CD pipeline fails:

1. **Check the Actions tab** in GitHub for detailed logs
2. **Reproduce locally** using the same `xcodebuild` command from ci.yml
3. **Verify Xcode version** matches CI (16.3+)
4. **Check for flaky tests** by running multiple times locally
5. **Review recent changes** for test-breaking modifications
6. See [troubleshooting.md](troubleshooting.md) for common issues

#### Common failure causes

- **Simulator not available:** CI boots simulator before running tests
- **Compilation errors:** Fix in code, tests will automatically re-run
- **Flaky tests:** Add retries or fix race conditions in tests
- **Timeout:** Tests taking too long (>10 minutes is unusual for unit tests)
- **Dependencies:** Clear SPM cache if package resolution fails

#### Xcode Cloud accidentally enabled

If Xcode Cloud starts building again:

1. Check App Store Connect → App Distribution → Xcode Cloud for enabled workflows
2. Disable all workflows or remove start conditions
3. Verify the `.xcode-cloud-disabled` file is still present in the repo
4. Consult with team if there was an intentional policy change

### Deployment Process

**Step-by-step deployment flow:**

1. Developer creates PR with changes
2. **CI validation runs** (`ci.yml`):
   - Code coverage validated (80% minimum)
   - API changes detected
   - Documentation checked
   - All tests pass
3. PR is reviewed and merged to `main`
4. **Deployment workflow triggers** (`deploy.yml`):
   - Build number auto-increments (e.g., 7 → 8)
   - **Build number is pushed to `main` before archive/upload** so a failed deploy cannot leave the repo stale and cause duplicate Firebase build numbers
   - Release notes generated from PR
   - App is built and signed
   - IPA uploaded to Firebase App Distribution
5. Testers receive notification in Firebase App Distribution

**Build versioning:**
- Marketing version: `1.000` (manual updates for releases)
- Build number: Auto-incremented on every deployment (current: `7`)
- Format: `Version 1.000 (Build 7)`

**Deploy safeguards:**
- **Concurrency:** Only one deploy runs at a time (`deploy-firebase-main` group)
- **Skip bump commits:** Pushes with message `Bump build number to … [skip ci]` do not re-trigger deploy
- **Skip CI on bumps:** `ci.yml` skips validation on `[skip ci]` commits
- **Push before build:** The incremented build number is committed and pushed to `main` before archiving/uploading to Firebase

**Troubleshooting duplicate Firebase build numbers**

If multiple Firebase releases show the same build number (e.g. three `1.000 (7)` entries), the usual cause is deploy runs that **uploaded an IPA but failed to push** the incremented `CURRENT_PROJECT_VERSION` back to `main`. Each subsequent run then read the same build number from the repo and produced the same Firebase build.

Common failure modes (July 2026):
1. Missing `contents: write` permission on deploy — push failed with 403 after Firebase upload
2. Manual `workflow_dispatch` runs from feature branches — upload succeeds but push to `main` is skipped
3. Concurrent deploy runs before concurrency was added — both read the same `CURRENT_PROJECT_VERSION`

The push-before-build ordering prevents new duplicates even when archive or Firebase upload fails later in the job.

### Future Enhancements

Planned or possible improvements to the CI/CD pipeline:

- ✅ **Build and archive:** Automated Firebase App Distribution _(completed in Step 2)_
- ✅ **Build number automation:** Auto-increment build numbers _(completed in Step 2)_
- ✅ **Release notes generation:** Extract PR info into release notes _(completed in Step 2)_
- **UI tests workflow:** Separate job for SpotUITests (longer runtime, separate from unit tests)
- **TestFlight distribution:** Add TestFlight upload option alongside Firebase
- **Static analysis:** SwiftLint, SwiftFormat, or similar tools
- **PR automation:** Danger for additional automated checks and comments
- **Coverage trending:** Track coverage changes over time
- **Performance tests:** Benchmark critical paths and track regressions
- **Deployment notifications:** Slack/Discord notifications on successful deploys

See `.github/workflows/README.md` for specific enhancement ideas.

### Re-enabling Xcode Cloud

If the team decides to re-enable Xcode Cloud in the future:

1. **Discuss strategy:** Decide if GitHub Actions should be replaced or run in parallel
2. **Remove marker file:** Delete `.xcode-cloud-disabled` from repository
3. **Configure workflows:** Set up workflows in App Store Connect
4. **Update documentation:** Revise this doc and workflow READMEs
5. **Update release process:** Modify [release-process.md](release-process.md) as needed
6. **Communicate to team:** Announce the CI/CD strategy change

## Related docs

- [.github/workflows/README.md](../../.github/workflows/README.md) — GitHub Actions workflows
- [firebase-distribution-setup.md](firebase-distribution-setup.md) — Firebase App Distribution setup guide
- [testing.md](testing.md) — Test organization and execution
- [release-process.md](release-process.md) — Pre-release and App Store process
- [troubleshooting.md](troubleshooting.md) — Common build and test failures
- [../diagrams/testing-release-flow.md](../diagrams/testing-release-flow.md) — Pipeline flow diagram

## Open questions / TODOs

- ~~Consider adding UI test workflow (SpotUITests) as separate job~~ (on roadmap)
- ~~Evaluate coverage reporting tools (Codecov, Coveralls, etc.)~~ (implemented with validate-coverage.sh)
- ~~Firebase build automation on merge to main~~ _(completed: deploy.yml)_
- ~~Build number automation and release notes generation~~ _(completed: deploy.yml)_
- Add SwiftLint or SwiftFormat for code style consistency (on roadmap)
- Configure required status checks in GitHub branch protection (should be enabled for production)
- Consider adding TestFlight distribution alongside Firebase
