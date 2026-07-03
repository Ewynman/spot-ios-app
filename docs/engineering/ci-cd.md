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

1. **Checkout:** Pull repository code
2. **Setup:** Install xcbeautify
3. **Cache:** Restore Swift Package Manager dependencies
4. **Test:** Run SpotTests scheme with code coverage enabled
5. **Artifacts:** Upload test results (`.xcresult`) and coverage reports

**What it validates:**
- All unit tests pass
- No compilation errors
- Code coverage is collected (for future analysis)

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

CI collects code coverage data on every run. Coverage reports are uploaded as artifacts and retained for 7 days.

**Future enhancements:**
- Add coverage reporting tool (e.g., Codecov)
- Set coverage thresholds and gates
- Display coverage trends in PRs

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

1. Runs the full unit test suite
2. Reports status as a check on the PR
3. Blocks merge if tests fail (when required checks are configured)
4. Shows test results and logs in the Actions tab

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
- **Build and archive:** Automated TestFlight distribution for release candidates
- **Static analysis:** SwiftLint, SwiftFormat, or similar tools
- **PR automation:** Danger for automated checks and comments
- **Coverage reporting:** Codecov or similar for coverage visualization
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

- Consider adding UI test workflow (SpotUITests) as separate job
- Evaluate coverage reporting tools (Codecov, Coveralls, etc.)
- Add SwiftLint or SwiftFormat for code style consistency
- Configure required status checks in GitHub branch protection
