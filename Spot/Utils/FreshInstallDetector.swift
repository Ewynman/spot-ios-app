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

            // Check if Firebase Auth has a persisted user
            if Auth.auth().currentUser != nil {
                SpotLogger.info("\(Constants.Analytics.authReinstall) hadKeychainUser=true action=autoSignOut")

                // Auto sign out the persisted user
                do {
                    try Auth.auth().signOut()

                    // Clear all local caches and session data
                    clearAllCaches()

                    return true
                } catch {
                    SpotLogger.error("Failed to auto sign out on fresh install: \(error.localizedDescription)")
                }
            } else {
                SpotLogger.info("\(Constants.Analytics.authReinstall) hadKeychainUser=false action=none")
            }
        }

        return false
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

        SpotLogger.info("FreshInstallDetector: Cleared all caches and session data")
    }
}
