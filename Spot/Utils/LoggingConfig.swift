//
//  LoggingConfig.swift
//  Spot
//
//  Centralized logging: defaults from `Config/LoggingDefaults.plist`, overrides in
//  Settings (DEBUG), and release builds limited to errors only.
//

import Foundation

enum LoggingConfig {

    private static let bundledDefaultsFileName = "LoggingDefaults"

    /// Register plist defaults, reset runtime flags, and apply the active scheme (DEBUG vs release).
    static func configure() {
        registerDefaultKeys()
        resetRuntimeFlags()

#if DEBUG
        applyDevelopmentLoggingFromUserDefaults()
#else
        SpotLogger.setMinimumLevel(.error)
        SpotLogger.mapOnlyLoggingEnabled = false
#endif
    }

    /// Re-read `UserDefaults` and reapply toggles (call after changing settings in-app).
    static func applyFromUserDefaults() {
#if DEBUG
        resetRuntimeFlags()
        applyDevelopmentLoggingFromUserDefaults()
#endif
    }

    // MARK: - Defaults registration

    private static func registerDefaultKeys() {
        var defaults: [String: Any] = [
            Constants.UserDefaultsKeys.debugLoggingEnabled: true,
            Constants.UserDefaultsKeys.logAllDebugCategories: false,
            Constants.UserDefaultsKeys.logSpotCard: false,
            Constants.UserDefaultsKeys.logPrivacy: false,
            Constants.UserDefaultsKeys.logFeedComponent: false,
            Constants.UserDefaultsKeys.logPostFlow: false,
            Constants.UserDefaultsKeys.logAuth: false,
            Constants.UserDefaultsKeys.logNetworkComponent: false,
            Constants.UserDefaultsKeys.logDeepLink: false
        ]

        if let fromPlist = loadBundledLoggingDefaultsPlist() {
            for (key, value) in fromPlist {
                defaults[key] = value
            }
        }

        UserDefaults.standard.register(defaults: defaults)
    }

    private static func loadBundledLoggingDefaultsPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: bundledDefaultsFileName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = root as? [String: Any] else {
            return nil
        }
        return dict
    }

    // MARK: - Runtime reset + DEBUG apply

    private static func resetRuntimeFlags() {
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
    }

#if DEBUG
    private static func applyDevelopmentLoggingFromUserDefaults() {
        let ud = UserDefaults.standard
        SpotLogger.setMinimumLevel(.debug)
        SpotLogger.setDebugLoggingEnabled(ud.bool(forKey: Constants.UserDefaultsKeys.debugLoggingEnabled))

        if ud.bool(forKey: Constants.UserDefaultsKeys.logAllDebugCategories) {
            SpotLogger.enableAllDebug = true
            enableAllDebugLogging()
            return
        }

        if ud.bool(forKey: Constants.UserDefaultsKeys.logSpotCard) {
            enableSpotCardLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logPrivacy) {
            enablePrivacyLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logFeedComponent) {
            enableFeedComponentLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logPostFlow) {
            enablePostFlowLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logAuth) {
            enableAuthLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logNetworkComponent) {
            enableNetworkComponentLogging()
        }
        if ud.bool(forKey: Constants.UserDefaultsKeys.logDeepLink) {
            enableDeepLinkLogging()
        }
    }
#endif

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
