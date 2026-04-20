//
//  FreshInstallDetector.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation
import Supabase

class FreshInstallDetector {
    static let shared = FreshInstallDetector()
    private init() {}

    /// Detects if this is a fresh install and clears a persisted Supabase session.
    /// Returns true if a session was cleared due to fresh install.
    @MainActor func handleFreshInstall() async -> Bool {
        let userDefaults = UserDefaults.standard
        let isFirstRun = !userDefaults.bool(forKey: Constants.UserDefaultsKeys.firstRun)

        if isFirstRun {
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.firstRun)
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.promptPermsOnNextLogin)

            if (try? await supabase.auth.session) != nil {
                SpotLogger.log(FreshInstallDetectorLogs.reinstallWithKeychainUser)
                Task { @MainActor in
                    AnalyticsService.shared.trackAuthEvent(Constants.Analytics.authReinstall, parameters: ["had_keychain_user": true, "action": "auto_sign_out"])
                }

                do {
                    try await supabase.auth.signOut()
                    clearAllCaches()
                    return true
                } catch {
                    SpotLogger.log(FreshInstallDetectorLogs.autoSignOutFailed, details: ["error": error.localizedDescription])
                }
            } else {
                SpotLogger.log(FreshInstallDetectorLogs.reinstallWithoutKeychainUser)
                Task { @MainActor in
                    AnalyticsService.shared.trackAuthEvent(Constants.Analytics.authReinstall, parameters: ["had_keychain_user": false, "action": "none"])
                }
            }
        }

        return false
    }

    /// Returns true once if we should prompt for permissions at next login; resets the flag.
    @MainActor func consumePromptPermissionsOnNextLoginFlag() -> Bool {
        let userDefaults = UserDefaults.standard
        let shouldPrompt = userDefaults.bool(forKey: Constants.UserDefaultsKeys.promptPermsOnNextLogin)
        if shouldPrompt {
            userDefaults.set(false, forKey: Constants.UserDefaultsKeys.promptPermsOnNextLogin)
        }
        return shouldPrompt
    }

    @MainActor private func clearAllCaches() {
        FeedCache.shared.clearCache()
        DeepLinkState.shared.clearUserSession()
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.notificationsRequested)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastKnownLocationStatus)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastKnownNotificationStatus)

        SpotLogger.log(FreshInstallDetectorLogs.clearedAllCaches)
    }
}
