//
//  SpotLaunchConfiguration.swift
//  Spot
//
//  Reads launch arguments / environment for UI tests. All flags are inert
//  outside DEBUG builds so TestFlight / App Store behavior is unchanged.
//

import Foundation

enum SpotLaunchConfiguration {

    /// True when UI tests set `SPOT_UI_TEST_MODE=1` (DEBUG only).
    static var isUITestMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SPOT_UI_TEST_MODE"] == "1"
        #else
        false
        #endif
    }

    /// Synthetic auth presentation for UI tests (requires `isUITestMode`).
    enum UITestAuthBootstrap: String {
        case loggedIn
        case loggedOut
    }

    static var uiTestAuthBootstrap: UITestAuthBootstrap? {
        #if DEBUG
        guard isUITestMode,
              let raw = ProcessInfo.processInfo.environment["SPOT_AUTH_STATE"],
              let value = UITestAuthBootstrap(rawValue: raw)
        else { return nil }
        return value
        #else
        nil
        #endif
    }

    /// Stable synthetic user id for UI tests (`SPOT_AUTH_STATE=loggedIn`).
    static let uiTestSyntheticUserId = "00000000-0000-0000-0000-0000000000AA"

    /// `SPOT_USER_TIER=pro` sets Pro in synthetic auth (DEBUG + UI test only).
    static var uiTestUserIsPro: Bool {
        #if DEBUG
        guard isUITestMode else { return false }
        return ProcessInfo.processInfo.environment["SPOT_USER_TIER"] == "pro"
        #else
        false
        #endif
    }

    /// Overrides account-deletion re-auth UI: `password` (default) or `apple`.
    static var uiTestAccountDeletionReauth: AccountDeletionReauthMethod? {
        #if DEBUG
        guard isUITestMode,
              let raw = ProcessInfo.processInfo.environment["SPOT_ACCOUNT_DELETION_REAUTH"]
        else { return nil }
        switch raw.lowercased() {
        case "apple": return .signInWithApple
        case "password": return .password
        default: return nil
        }
        #else
        nil
        #endif
    }
}
