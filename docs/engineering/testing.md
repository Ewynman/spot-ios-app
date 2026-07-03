# Testing

## Purpose

Testing philosophy, schemes, how to run tests, and what to cover.

## Audience

Engineers and CI owners.

## Current status

Matches `.cursor/rules/project.mdc` and Xcode schemes **Spot**, **SpotTests**, **SpotUITests**.

## Details

### Philosophy

- **Unit tests** for deterministic logic (validators, ranking helpers, deep link parsing, map policy, view model rules) with mocks—no live network or Apple sign-in prompts.
- **UI tests** for stable smoke flows using `accessibilityIdentifier` where possible.

### Schemes

| Scheme | Runs |
| --- | --- |
| **Spot** | App; test action may run `Spot.xctestplan` (unit + UI). |
| **SpotTests** | `SpotTests` only — fast. |
| **SpotUITests** | `SpotUITests` + `SpotUITests.xctestplan`. |

### What should be tested (non-exhaustive)

- Auth gating and session edge cases (unit where mockable).
- Posting flow state machine and moderation client behavior.
- Draft behavior when testable without device-only APIs.
- Supabase repository behavior behind protocols/mocks (**TODO: verify** mock coverage depth).
- **Map drawer** selection / dismiss policy (`MapDiscoveryDrawerPolicyTests`, panel height tests, etc.).
- **Data plane guard** — `DataPlaneGuardTests` ensures no legacy Firebase Firestore/Storage upload code under `Spot/`.
- Onboarding managers (`HomeTourManagerTests`, etc.).
- **Pro** gating helpers (`ProEntitlementChecker`, subscription manager error paths).
- **Universal Links** parsing (`DeepLinkRouter` tests if present—**TODO: verify** file names).
- **Private accounts** — `AuthorPrivacyCacheTests`, `FollowRequestsServiceTests`, and `PrivateAccountIntegrationTests` cover privacy filtering, follow requests, and content visibility. See [../testing/private-account-tests.md](../testing/private-account-tests.md) for details.

### Commands

```sh
SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | head -n 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
BEAUTIFY=$(command -v xcbeautify >/dev/null && echo "xcbeautify" || echo "cat")

xcodebuild -scheme SpotTests -destination "id=$SIM_ID" test | $BEAUTIFY
xcodebuild -scheme SpotUITests -destination "id=$SIM_ID" test | $BEAUTIFY
```

### Adding tests

- Place Swift Testing tests in **`SpotTests/`**.
- Place XCTest UI tests in **`SpotUITests/`**.
- Do not cross-contaminate targets (per project rules).

### SwiftUI previews

Add previews for new or heavily changed UI when practical to speed design review.

## Related docs

- [local-setup.md](local-setup.md)
- [../diagrams/testing-release-flow.md](../diagrams/testing-release-flow.md)
- [../testing/private-account-tests.md](../testing/private-account-tests.md)

## Open questions / TODOs

- List top 10 critical UI smoke tests by identifier: TODO: verify in `SpotUITests`.
