//
//  AppDelegate.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAnalytics

class AppDelegate: NSObject, UIApplicationDelegate {
    private var memoryWarningObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Firebase early
        FirebaseApp.configure()


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

        // Configure logging defaults.
        LoggingConfig.configure()

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageService.shared.clearCache()
            RemoteImageMemory.clearCache()
            URLCache.shared.removeAllCachedResponses()
            Task { await MapViewportLoader.shared.clearCache() }
            SpotLogger.log(AppDelegateLogs.memoryWarning)
        }

        SubscriptionManager.shared.startListeningForTransactionUpdates()

        return true
    }

    // MARK: - Deep Link & URL Handling

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            SpotLogger.log(AppDelegateLogs.universalLinkOnLaunch)
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
        SpotLogger.log(AppDelegateLogs.customSchemeUrlOnLaunch, details: ["url": url.absoluteString])
        DeepLinkState.shared.handleDeepLink(url, origin: .customScheme, isColdStart: true)
        return true
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
}
