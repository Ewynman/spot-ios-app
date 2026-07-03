# CI/CD Pipeline

## Purpose

Documents the continuous integration and continuous deployment pipeline for the Spot iOS app.

## Audience

Developers, release owners, and anyone maintaining or troubleshooting the build pipeline.

## Current status

Custom CI/CD pipeline is active. **Xcode Cloud is disabled** to avoid redundant builds and reduce Apple build minutes consumption.

## Details

### Pipeline overview

The Spot project uses a custom CI/CD pipeline instead of Xcode Cloud. This pipeline handles:

- Automated testing on pull requests
- Build validation
- Pre-release checks
- TestFlight distribution (when configured)

### Xcode Cloud status

**Xcode Cloud is intentionally disabled** for this repository.

#### Why disabled

- **Single source of truth:** Custom pipeline is the sole CI/CD system
- **Cost management:** Avoids consuming Apple build minutes unnecessarily
- **Consistency:** All builds use the same pipeline configuration
- **Control:** Better control over build triggers and conditions

#### Marker file

The repository includes a `.xcode-cloud-disabled` marker file at the root to document this decision and prevent accidental re-enabling.

#### Keeping it disabled

Xcode Cloud is configured through App Store Connect, not repository files. To keep it disabled:

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to your app → **Xcode Cloud** tab
3. Ensure all workflows are **disabled** or **deleted**
4. Do not enable "Start Conditions" for:
   - Branch Changes
   - Pull Requests
   - Tag Changes

### Custom pipeline

The custom pipeline configuration lives in the repository and is maintained alongside the codebase.

#### Build triggers

- Pull request creation and updates
- Commits to main branch (configurable)
- Manual workflow dispatch

#### Pipeline stages

1. **Setup:** Install dependencies, configure environment
2. **Build:** Compile the app with Xcode
3. **Test:** Run SpotTests (unit) and SpotUITests (UI) as appropriate
4. **Validate:** Verify build artifacts and test results
5. **Archive:** (Optional) Create distribution archive for TestFlight

#### Test execution

- **Unit tests** (`SpotTests`): Run on every PR
- **UI tests** (`SpotUITests`): Run on significant UI changes or manually
- See [testing.md](testing.md) for test organization and schemes

### Local vs CI builds

#### Local development

Developers can run the same tests locally using:

```bash
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
BEAUTIFY=$(command -v xcbeautify >/dev/null && echo "xcbeautify" || echo "cat")

# Build
xcodebuild -scheme Spot -destination "id=$SIM_ID" build | $BEAUTIFY

# Test
xcodebuild -scheme Spot -destination "id=$SIM_ID" test | $BEAUTIFY
```

#### CI environment

The CI environment should mirror local builds as closely as possible:
- Same Xcode version
- Same simulator OS versions
- Same build settings and schemes

### Troubleshooting

#### Pipeline failures

If the CI/CD pipeline fails:

1. Check the build logs for compilation errors
2. Verify tests pass locally with the same Xcode version
3. Check for environment-specific issues (secrets, permissions)
4. See [troubleshooting.md](troubleshooting.md) for common issues

#### Xcode Cloud accidentally enabled

If Xcode Cloud starts building again:

1. Check App Store Connect → Xcode Cloud for enabled workflows
2. Disable all workflows or remove start conditions
3. Verify the `.xcode-cloud-disabled` file is still present in the repo
4. Check with the team if there was an intentional policy change

### Re-enabling Xcode Cloud

If the team decides to re-enable Xcode Cloud in the future:

1. **Discuss with the team** the rationale and updated CI/CD strategy
2. **Remove** the `.xcode-cloud-disabled` marker file
3. **Configure** workflows in App Store Connect
4. **Update this documentation** to reflect the new pipeline architecture
5. **Update** [release-process.md](release-process.md) as needed

## Related docs

- [testing.md](testing.md) — Test organization and execution
- [release-process.md](release-process.md) — Pre-release and App Store process
- [troubleshooting.md](troubleshooting.md) — Common build and test failures
- [../diagrams/testing-release-flow.md](../diagrams/testing-release-flow.md) — Pipeline flow diagram

## Open questions / TODOs

- Document specific custom pipeline configuration location once finalized
- Add links to CI/CD dashboard or logs when available
- Document TestFlight automation integration when configured
