# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for the Spot iOS app.

## Workflows

### `ci.yml` - Continuous Integration

**Triggers:**
- Pull requests to `main`
- Pushes to `main` (except `[skip ci]` commits)

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

---

### `deploy.yml` - Firebase App Distribution Deployment

**Triggers:**
- Merges to `main` (after CI passes)
- Manual workflow dispatch

**What it does:**
- Automatically increments build number in `CURRENT_PROJECT_VERSION`
- Pushes build number update to `main` before building (prevents duplicate Firebase build numbers)
- Extracts release notes from merged PR (title + body)
- Injects Firebase configuration (`GoogleService-Info.plist`) from secrets
- Installs Apple signing certificates and provisioning profiles
- Archives and exports signed IPA for distribution
- Uploads to Firebase App Distribution for the `testers` group
- Creates deployment summary in GitHub Actions

**Required GitHub Secrets:**
- `GOOGLE_SERVICE_INFO_PLIST_BASE64` - Firebase GoogleService-Info.plist (base64 encoded)
- `FIREBASE_APP_ID` - Firebase iOS App ID
- `FIREBASE_SERVICE_ACCOUNT_JSON` - Firebase service account credentials (JSON)
- `APPLE_CERTIFICATE_BASE64` - Distribution certificate (.p12, base64 encoded)
- `APPLE_CERTIFICATE_PASSWORD` - Certificate password
- `PROVISIONING_PROFILE_BASE64` - Provisioning profile (base64 encoded)
- `KEYCHAIN_PASSWORD` - Temporary keychain password (any secure random string)

See [docs/engineering/firebase-distribution-setup.md](../../docs/engineering/firebase-distribution-setup.md) for detailed setup instructions.

**Build versioning:**
- Marketing version: `1.000` (manual updates)
- Build number: Auto-incremented on every deploy (e.g., 7 → 8)

**Important notes:**
- GoogleService-Info.plist is required for Firebase initialization - without it, the app will crash on launch
- Build number is committed and pushed before archiving to prevent duplicate Firebase builds
- Concurrent deploys are serialized via the `deploy-firebase-main` concurrency group
- Bump commits (`Bump build number to ... [skip ci]`) do not re-trigger CI or deploy workflows

---

## Requirements

### CI Requirements

The CI workflow expects:
- A valid `SpotTests` scheme in the Xcode project
- Tests that can run on iOS Simulator
- No manual provisioning profiles required for unit tests
- `jq` installed (for JSON parsing in validation scripts)
- Validation scripts in `scripts/` directory:
  - `validate-api-changes.sh`
  - `validate-documentation.sh`
  - `validate-coverage.sh`

### Deploy Requirements

The deploy workflow requires:
- All seven GitHub secrets configured (see above)
- Valid Apple Distribution certificate and provisioning profile
- Firebase project with App Distribution enabled
- `testers` group created in Firebase App Distribution
- Valid `GoogleService-Info.plist` from Firebase Console

---

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

---

## Troubleshooting

### "App crashes immediately on launch" after Firebase App Distribution download

**Cause**: Missing `GOOGLE_SERVICE_INFO_PLIST_BASE64` secret in GitHub repository settings.

**Solution**: 
1. Download `GoogleService-Info.plist` from Firebase Console
2. Convert to base64: `base64 -i GoogleService-Info.plist | pbcopy`
3. Add as `GOOGLE_SERVICE_INFO_PLIST_BASE64` secret in GitHub repository settings
4. Re-run the deployment workflow

See [docs/engineering/firebase-distribution-setup.md](../../docs/engineering/firebase-distribution-setup.md) for full setup guide.

### Duplicate Firebase build numbers

**Cause**: Deploy workflow uploaded an IPA but failed to push the incremented build number back to `main`.

**Solution**: The workflow now commits and pushes build numbers *before* archiving, preventing this issue. If you encounter duplicate builds from old deploys, they can be ignored - new deploys will use the correct incremented number.

---

## Future Enhancements

Consider adding:
- ✅ Firebase App Distribution automation (completed)
- ✅ Build number automation (completed)
- ✅ Release notes generation (completed)
- UI test workflow (separate from unit tests due to longer runtime)
- TestFlight upload option alongside Firebase
- SwiftLint or other static analysis tools
- Danger for additional automated PR checks
- Coverage trending over time
- Deployment notifications (Slack/Discord)
