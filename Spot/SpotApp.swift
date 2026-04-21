//
//  SpotApp.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import FirebaseCrashlytics

@main
struct SpotApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var deepLinkState = DeepLinkState.shared
    @State private var showLaunchScreen = true

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {}

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
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
                        .task {
                            SubscriptionManager.shared.startTransactionUpdatesListener { [weak authViewModel] hasPro, expirationDate in
                                guard hasPro, let authViewModel else { return }
                                await authViewModel.setProActive(true, proUntil: expirationDate)
                            }
                            _ = await FreshInstallDetector.shared.handleFreshInstall()
                            deepLinkState.processPendingDeepLinks()
                        }
                }
            }
        }
    }
}
