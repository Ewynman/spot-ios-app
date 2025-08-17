//
//  AppDelegate.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import UIKit
import SwiftUI
import FirebaseCore
import FirebaseCrashlytics

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Firebase configured in SpotApp.init(); ensure Crashlytics is enabled
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        Crashlytics.crashlytics().log("AppDelegate didFinishLaunching")
        return true
    }
    
    // Handle Universal Links that launch the app
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            SpotLogger.info("AppDelegate: Received Universal Link on app launch")
            DeepLinkState.shared.handleInitialUserActivity(userActivity)
            return true
        }
        return false
    }
    
    // Handle custom URL schemes that launch the app
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        SpotLogger.info("AppDelegate: Received custom scheme URL on app launch: \(url.absoluteString)")
        DeepLinkState.shared.handleDeepLink(url, origin: .customScheme, isColdStart: true)
        return true
    }
}
