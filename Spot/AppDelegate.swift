//
//  AppDelegate.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Firebase early
        FirebaseApp.configure()

        // Configure Firebase App Check
        #if DEBUG
        // Use Debug provider for Simulator and local builds
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        // Use DeviceCheck (or AppAttestProviderFactory if you registered that)
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif

        // Enable Crashlytics collection
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Crashlytics.crashlytics().log("AppDelegate didFinishLaunching")

        // Configure logging (default: info + error only, debug categories disabled)
        LoggingConfig.configure()
        
        // Uncomment to enable specific component logging:
        // LoggingConfig.enableSpotCardLogging()         // SpotCard UI and image logs
        // LoggingConfig.enablePrivacyLogging()          // Privacy filtering logs
        // LoggingConfig.enableFeedLogging()             // Feed category only
        // LoggingConfig.enableFeedComponentLogging()    // Feed components + category
        // LoggingConfig.enablePostFlowLogging()         // Post flow, moderation, location
        LoggingConfig.enableAuthLogging()               // Authentication logs
        LoggingConfig.enableNetworkLogging()            // Network category only
        // LoggingConfig.enableNetworkComponentLogging() // Network components + category
        // LoggingConfig.enableDeepLinkLogging()         // Deep link routing
        
        // Or enable individual components:
        // ComponentLogging.spotCard = true
        // ComponentLogging.authorPrivacyCache = true
        // ComponentLogging.feedRepository = true
        
        // Or enable by category:
        // DebugCategory.enable(.privacy)
        // DebugCategory.enable(.feed)

        return true
    }

    // MARK: - Deep Link & URL Handling

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            SpotLogger.info("AppDelegate: Received Universal Link on app launch")
            DeepLinkState.shared.handleInitialUserActivity(userActivity)
            return true
        }
        return false
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        SpotLogger.info("AppDelegate: Received custom scheme URL on app launch: \(url.absoluteString)")
        DeepLinkState.shared.handleDeepLink(url, origin: .customScheme, isColdStart: true)
        return true
    }
}
