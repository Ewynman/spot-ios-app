//
//  LoggingConfig.swift
//  Spot
//
//  Created for centralized logging configuration
//

import Foundation

/// Centralized logging configuration
/// Use this to enable/disable debug categories at app startup
struct LoggingConfig {
    /// Configure debug logging categories
    /// Call this in AppDelegate or App init to control what debug logs are enabled
    static func configure() {
        let defaults: [String: Any] = [
            Constants.UserDefaultsKeys.debugLoggingEnabled: false,
            Constants.UserDefaultsKeys.logSpotCard: false,
            Constants.UserDefaultsKeys.logPrivacy: false,
            Constants.UserDefaultsKeys.logFeedComponent: false,
            Constants.UserDefaultsKeys.logPostFlow: false,
            Constants.UserDefaultsKeys.logAuth: false,
            Constants.UserDefaultsKeys.logNetworkComponent: false,
            Constants.UserDefaultsKeys.logDeepLink: false
        ]
        UserDefaults.standard.register(defaults: defaults)

        // Reset all dynamic logging flags before applying selected presets.
        DebugCategory.disableAll()
        SpotLogger.enableAllDebug = false
        SpotLogger.mapOnlyLoggingEnabled = false
        ComponentLogging.spotCard = false
        ComponentLogging.profileView = false
        ComponentLogging.searchView = false
        ComponentLogging.feedView = false
        ComponentLogging.authorPrivacyCache = false
        ComponentLogging.feedRepository = false
        ComponentLogging.feedRanker = false
        ComponentLogging.spotService = false
        ComponentLogging.authService = false
        ComponentLogging.imageService = false
        ComponentLogging.deepLinkRouter = false
        ComponentLogging.authViewModel = false
        ComponentLogging.likesViewModel = false
        ComponentLogging.bookmarksViewModel = false
        ComponentLogging.postFlow = false
        ComponentLogging.locationSelection = false
        ComponentLogging.photoSelection = false
        FeedFlags.enableDiagnosticLogging = false

    #if DEBUG
        SpotLogger.setMinimumLevel(.debug)
        SpotLogger.setDebugLoggingEnabled(UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.debugLoggingEnabled))

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logSpotCard) {
            enableSpotCardLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logPrivacy) {
            enablePrivacyLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logFeedComponent) {
            enableFeedComponentLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logPostFlow) {
            enablePostFlowLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logAuth) {
            enableAuthLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logNetworkComponent) {
            enableNetworkComponentLogging()
        }
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.logDeepLink) {
            enableDeepLinkLogging()
        }
#else
        SpotLogger.setMinimumLevel(.error)
#endif
    }
    
    // MARK: - Category-Based Presets (Simple)
    
    static func enableUILogging() {
        DebugCategory.enable(.ui)
        DebugCategory.enable(.navigation)
    }
     
    static func enableFeedLogging() {
        DebugCategory.enable(.feed)
        FeedFlags.enableDiagnosticLogging = true
    }
    
    static func enableNetworkLogging() {
        DebugCategory.enable(.network)
    }
    
    static func enableImageLogging() {
        DebugCategory.enable(.image)
    }
    
    static func enableAllDebugLogging() {
        DebugCategory.enableAll()
        SpotLogger.enableAllDebug = true
        FeedFlags.enableDiagnosticLogging = true
    }
    
    // MARK: - Component-Specific Presets (Includes component flags)
    
    static func enableSpotCardLogging() {
        ComponentLogging.spotCard = true
        DebugCategory.enable(.ui)
        DebugCategory.enable(.image)
    }
    
    static func enablePrivacyLogging() {
        ComponentLogging.authorPrivacyCache = true
        DebugCategory.enable(.privacy)
    }
    
    static func enableFeedComponentLogging() {
        ComponentLogging.feedRepository = true
        ComponentLogging.feedRanker = true
        DebugCategory.enable(.feed)
        FeedFlags.enableDiagnosticLogging = true
    }
    
    static func enablePostFlowLogging() {
        ComponentLogging.postFlow = true
        ComponentLogging.locationSelection = true
        ComponentLogging.photoSelection = true
        DebugCategory.enable(.moderation)
        DebugCategory.enable(.location)
    }
    
    static func enableAuthLogging() {
        ComponentLogging.authService = true
        ComponentLogging.authViewModel = true
        DebugCategory.enable(.auth)
    }
    
    static func enableNetworkComponentLogging() {
        ComponentLogging.spotService = true
        ComponentLogging.imageService = true
        DebugCategory.enable(.network)
        DebugCategory.enable(.image)
    }
    
    static func enableDeepLinkLogging() {
        ComponentLogging.deepLinkRouter = true
        DebugCategory.enable(.deepLink)
    }
}
