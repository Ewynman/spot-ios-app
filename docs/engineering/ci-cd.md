# CI/CD Pipeline

## Purpose

Documents the continuous integration and continuous deployment pipeline for the Spot iOS app.

## Audience

Developers, release owners, and anyone maintaining or troubleshooting the build pipeline.

## Current status

**GitHub Actions** is the active CI/CD system. **Xcode Cloud is disabled** to avoid redundant builds and maintain a single source of truth.

## Details

### CI/CD System: GitHub Actions

The Spot project uses GitHub Actions for continuous integration. Configuration lives in `.github/workflows/`.

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

### Future Enhancements

Planned or possible improvements to the CI/CD pipeline:

- **UI tests workflow:** Separate job for SpotUITests (longer runtime, separate from unit tests)
- **Build and archive:** Automated TestFlight distribution for release candidates (step 2/3 of roadmap)
- **Firebase build triggers:** Automatic Firebase builds on merge to main (step 2/3 of roadmap)
- **Build number automation:** Auto-increment build numbers on release builds
- **Release notes generation:** Extract PR info into release notes
- **Static analysis:** SwiftLint, SwiftFormat, or similar tools
- **PR automation:** Danger for additional automated checks and comments
- **Coverage trending:** Track coverage changes over time
- **Performance tests:** Benchmark critical paths and track regressions
- **Manual dispatch:** Workflow dispatch for on-demand test runs

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
- [testing.md](testing.md) — Test organization and execution
- [release-process.md](release-process.md) — Pre-release and App Store process
- [troubleshooting.md](troubleshooting.md) — Common build and test failures
- [../diagrams/testing-release-flow.md](../diagrams/testing-release-flow.md) — Pipeline flow diagram

## Open questions / TODOs

- ~~Consider adding UI test workflow (SpotUITests) as separate job~~ (on roadmap)
- ~~Evaluate coverage reporting tools (Codecov, Coveralls, etc.)~~ (implemented with validate-coverage.sh)
- ~~Add SwiftLint or SwiftFormat for code style consistency~~ (on roadmap)
- ~~Configure required status checks in GitHub branch protection~~ (should be enabled for production)
- **Next steps (2/3):** Firebase build automation on merge to main
- **Next steps (3/3):** Build number automation and release notes generation
