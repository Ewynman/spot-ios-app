//
//  FreshInstallDetector.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation
import FirebaseAuth

class FreshInstallDetector {
    static let shared = FreshInstallDetector()
    private init() {}

    /// Detects if this is a fresh install and handles Firebase Auth persistence
    /// Returns true if user was auto-signed out due to fresh install
    @MainActor func handleFreshInstall() -> Bool {
        let userDefaults = UserDefaults.standard
        let isFirstRun = !userDefaults.bool(forKey: Constants.UserDefaultsKeys.firstRun)

        if isFirstRun {
            // Mark as not first run
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.firstRun)
            // Ensure we prompt permissions only on next successful login
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.promptPermsOnNextLogin)

            // Check if Firebase Auth has a persisted user
            if Auth.auth().currentUser != nil {
                SpotLogger.log(FreshInstallDetectorLogs.reinstallWithKeychainUser)
                Task { @MainActor in
                    AnalyticsService.shared.trackAuthEvent(Constants.Analytics.authReinstall, parameters: ["had_keychain_user": true, "action": "auto_sign_out"])
                }

                // Auto sign out the persisted user
                do {
                    try Auth.auth().signOut()

                    // Clear all local caches and session data
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
        // Clear feed caches
        FeedCache.shared.clearCache()

        // Clear deep link state
        DeepLinkState.shared.clearUserSession()

        // Clear any other session data
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.notificationsRequested)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastKnownLocationStatus)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastKnownNotificationStatus)

        SpotLogger.log(FreshInstallDetectorLogs.clearedAllCaches)
    }
}
