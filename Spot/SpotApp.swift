//
//  SpotApp.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAppCheck

@main
struct SpotApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var deepLinkState = DeepLinkState.shared
    @State private var showLaunchScreen = true

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        FirebaseApp.configure()
        // Optional: enable collection immediately for local builds
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView()
                        .onAppear {
                            // Show launch screen for 6 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showLaunchScreen = false
                                }
                            }
                        }
                } else {
                    RootView()
                        .environmentObject(authViewModel)
                        .environmentObject(deepLinkState)
                        .environmentObject(PermissionManager.shared)
                        .onAppear {
                            // Handle fresh install detection
                            _ = FreshInstallDetector.shared.handleFreshInstall()

                            // Process any pending deep links after app is ready
                            deepLinkState.processPendingDeepLinks()
                        }
                }
            }
        }

    }
}
