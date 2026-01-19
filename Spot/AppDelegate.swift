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
import FirebaseAnalytics

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
        
        // Configure Firebase Analytics
        #if DEBUG
        // Disable analytics collection in debug builds (optional, for privacy)
        // Analytics.setAnalyticsCollectionEnabled(false)
        #else
        Analytics.setAnalyticsCollectionEnabled(true)
        #endif

        // Configure logging - ENABLE ALL LOGS
        LoggingConfig.configure()
        
        // Enable all debug logging (categories, components, and minimum level)
        LoggingConfig.enableAllDebugLogging()
        
        // Set minimum log level to debug to show all logs
        SpotLogger.setMinimumLevel(.debug)
        
        // Enable ALL component logging flags
        ComponentLogging.spotCard = true
        ComponentLogging.profileView = true
        ComponentLogging.searchView = true
        ComponentLogging.feedView = true
        ComponentLogging.authorPrivacyCache = true
        ComponentLogging.feedRepository = true
        ComponentLogging.feedRanker = true
        ComponentLogging.postFlow = true
        ComponentLogging.locationSelection = true
        ComponentLogging.photoSelection = true
        ComponentLogging.authService = true
        ComponentLogging.authViewModel = true
        ComponentLogging.likesViewModel = true
        ComponentLogging.bookmarksViewModel = true
        ComponentLogging.spotService = true
        ComponentLogging.spotUploader = true
        ComponentLogging.imageService = true
        ComponentLogging.deepLinkRouter = true
        
        // Enable all debug categories
        DebugCategory.enableAll()
        
        // Enable feed diagnostic logging
        FeedFlags.enableDiagnosticLogging = true

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
