# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for the Spot iOS app.

**Note:** Xcode Cloud is disabled for this repository. GitHub Actions is the sole CI/CD system. See `../../docs/engineering/ci-cd.md` for details.

## Workflows

### `ci.yml` - Continuous Integration

**Triggers:**
- Pull requests to `main`
- Pushes to `main`

**What it does:**
- Runs full unit test suite using the `SpotTests` scheme
- Uses macOS 15 runners with Xcode 16.3 (includes Swift 6.1 required by swift-crypto@4.5.0)
- Boots an iPhone simulator and executes tests
- Enables code coverage collection
- Uploads test results and coverage reports as artifacts

**Test output:**
- Test results are formatted with `xcbeautify` for readable output
- Test results (`.xcresult` bundles) are uploaded as artifacts for 7 days
- Code coverage reports are uploaded as artifacts for 7 days

## Requirements

The workflow expects:
- A valid `SpotTests` scheme in the Xcode project
- Tests that can run on iOS Simulator
- No manual provisioning profiles required for unit tests

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
- SwiftLint or other static analysis tools
- Danger for automated PR checks
