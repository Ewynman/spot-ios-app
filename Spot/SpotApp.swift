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
        // Firebase initialization moved to AppDelegate for consistency
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView()
                        .onAppear {
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
                            _ = FreshInstallDetector.shared.handleFreshInstall()
                            deepLinkState.processPendingDeepLinks()
                        }
                }
            }
        }
    }
}
