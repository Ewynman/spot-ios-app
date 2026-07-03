# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for the Spot iOS app.

## Workflows

### `ci.yml` - Continuous Integration

**Triggers:**
- Pull requests to `main`
- Pushes to `main`

**What it does:**
- Runs comprehensive PR validation including:
  - **API Breaking Change Detection**: Scans for changes to public Swift APIs
  - **Documentation Validation**: Checks if documentation needs updates
  - **Unit Tests**: Runs full test suite using the `SpotTests` scheme
  - **Code Coverage Enforcement**: Validates 80% minimum coverage on changed files
- Uses macOS 15 runners with Xcode 16.3 (includes Swift 6.1 required by swift-crypto@4.5.0)
- Boots an iPhone simulator and executes tests
- Enables code coverage collection
- Posts validation results as PR comment
- Uploads test results and coverage reports as artifacts

**Validation Scripts:**

The workflow uses three validation scripts in `scripts/`:

1. **`validate-api-changes.sh`**
   - Detects potential breaking changes to public APIs
   - Checks for removed/modified public functions, classes, structs, enums
   - Warns if breaking changes detected (doesn't fail PR, but alerts reviewers)

2. **`validate-documentation.sh`**
   - Validates documentation updates for code changes
   - Checks specific patterns (e.g., service changes → architecture docs)
   - Provides suggestions for which docs may need updates

3. **`validate-coverage.sh`**
   - Enforces 80% minimum coverage on changed production files
   - Uses `xcrun xccov` to extract coverage from `.xcresult` bundles
   - Fails PR if coverage threshold not met
   - Shows detailed per-file coverage breakdown

**Test output:**
- Test results are formatted with `xcbeautify` for readable output
- Test results (`.xcresult` bundles) are uploaded as artifacts for 7 days
- Code coverage reports are uploaded as artifacts for 7 days
- Validation results posted as PR comment with pass/fail status

## Requirements

The workflow expects:
- A valid `SpotTests` scheme in the Xcode project
- Tests that can run on iOS Simulator
- No manual provisioning profiles required for unit tests
- `jq` installed (for JSON parsing in validation scripts)
- Validation scripts in `scripts/` directory:
  - `validate-api-changes.sh`
  - `validate-documentation.sh`
  - `validate-coverage.sh`

## Local Testing

To run the same tests locally that CI runs:

```bash
# Get first available iPhone simulator
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')

# Run unit tests
xcodebuild \
  -scheme SpotTests \
  -destination "id=$SIM_ID" \
  -enableCodeCoverage YES \
  test | xcbeautify
```

## Future Enhancements

Consider adding:
- UI test workflow (separate from unit tests due to longer runtime)
- Build and archive workflow for release candidates
- **Firebase build automation** (step 2/3 of CI/CD roadmap)
- **Build number automation** (step 2/3 of CI/CD roadmap)
- **Release notes generation** from PR data (step 3/3 of CI/CD roadmap)
- SwiftLint or other static analysis tools
- Danger for additional automated PR checks
- Coverage trending over time
