# Validation Scripts

This directory contains CI/CD validation scripts used by GitHub Actions workflows to enforce code quality standards.

## Scripts

### `validate-coverage.sh`

Enforces minimum code coverage requirements on changed files in pull requests.

**Usage:**
```bash
./scripts/validate-coverage.sh <xcresult-path> <base-branch> <coverage-threshold>
```

**Arguments:**
- `xcresult-path`: Path to the `.xcresult` bundle from test execution
- `base-branch`: Base branch to compare against (default: `origin/main`)
- `coverage-threshold`: Minimum coverage percentage (default: `80`)

**What it does:**
- Extracts coverage data using `xcrun xccov`
- Identifies changed Swift files via `git diff`
- Calculates line coverage for each changed file
- Fails if any file is below the threshold
- Provides detailed per-file coverage breakdown

**Requirements:**
- `jq` for JSON parsing
- `git` for diff comparison
- `xcrun` with xccov

**Example:**
```bash
# Run after tests
./scripts/validate-coverage.sh TestResults.xcresult origin/main 80
```

### `validate-api-changes.sh`

Detects potential breaking changes to public Swift APIs.

**Usage:**
```bash
./scripts/validate-api-changes.sh <base-branch>
```

**Arguments:**
- `base-branch`: Base branch to compare against (default: `origin/main`)

**What it checks:**
- Removed public functions, classes, structs, enums, protocols
- Modified function signatures
- Changed public properties
- Deleted files containing public APIs

**Result:**
- Warns if breaking changes are detected
- Does not fail the build (warning only)
- Helps reviewers identify compatibility concerns

**Example:**
```bash
./scripts/validate-api-changes.sh origin/main
```

### `validate-documentation.sh`

Validates that documentation is updated when significant code changes are made.

**Usage:**
```bash
./scripts/validate-documentation.sh <base-branch>
```

**Arguments:**
- `base-branch`: Base branch to compare against (default: `origin/main`)

**What it checks:**
- Service/repository changes → architecture docs
- ViewModel changes → product docs
- Database migrations → database-and-rls.md
- Auth changes → networking-and-auth.md
- Storage/media changes → storage-and-media.md
- Configuration changes → configuration.md
- Deep link changes → universal-links.md

**Result:**
- Warns with specific suggestions if docs may need updates
- Does not fail the build (warning only)
- Guides developers to relevant documentation files

**Example:**
```bash
./scripts/validate-documentation.sh origin/main
```

## Running Locally

All scripts can be run locally before pushing to verify your changes will pass CI:

```bash
# 1. Run tests with coverage
xcodebuild \
  -scheme SpotTests \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult \
  test

# 2. Validate coverage
./scripts/validate-coverage.sh TestResults.xcresult origin/main 80

# 3. Check for API changes
./scripts/validate-api-changes.sh origin/main

# 4. Validate documentation
./scripts/validate-documentation.sh origin/main
```

## CI Integration

These scripts are integrated into the GitHub Actions workflow at `.github/workflows/ci.yml`:

- **API validation** runs before tests
- **Documentation validation** runs before tests
- **Tests** run with coverage enabled
- **Coverage validation** runs after tests

See [.github/workflows/README.md](../.github/workflows/README.md) for workflow documentation.

## Customization

### Adjusting Coverage Threshold

To change the coverage threshold for a specific PR (not recommended):

```bash
./scripts/validate-coverage.sh TestResults.xcresult origin/main 70
```

Or update the workflow file to change the default threshold:

```yaml
- name: Validate Code Coverage
  run: |
    ./scripts/validate-coverage.sh TestResults.xcresult origin/${{ github.base_ref }} 90
```

### Exempting Files

If a file legitimately cannot meet coverage requirements:

1. Discuss with the team
2. Document the reason in the PR
3. Consider refactoring to make the code more testable
4. As a last resort, the coverage check can be skipped for specific PRs (requires admin override)

## Troubleshooting

### Coverage validation fails with "No coverage data"

- Ensure tests ran successfully
- Verify `-enableCodeCoverage YES` was used
- Check that the `.xcresult` path is correct
- Ensure changed files have executable code (not just data models)

### API validation shows false positives

- The script uses simple pattern matching, not full AST parsing
- False positives can occur with complex Swift syntax
- Review the warning and determine if it's a real breaking change
- Document any intentional breaking changes in the PR

### Documentation validation suggests unnecessary updates

- The script uses heuristics to suggest documentation updates
- Not all suggestions are required
- Use judgment to determine if documentation truly needs updating
- Follow the guidelines in `docs/operations/documentation-maintenance.md`

## Related Documentation

- [CI/CD Pipeline](../docs/engineering/ci-cd.md)
- [Testing](../docs/engineering/testing.md)
- [Documentation Maintenance](../docs/operations/documentation-maintenance.md)
- [GitHub Actions Workflows](../.github/workflows/README.md)
