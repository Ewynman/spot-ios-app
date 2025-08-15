//
//  SpotApp.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import FirebaseCore

@main
struct SpotApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var deepLinkState = DeepLinkState.shared
    @State private var showLaunchScreen = true

    init() {
        FirebaseApp.configure()
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
                        .onAppear {
                            // Process any pending deep links after app is ready
                            deepLinkState.processPendingDeepLinks()
                        }
                }
            }
        }
        .onOpenURL { url in
            // Handle custom scheme URLs
            SpotLogger.info("SpotApp: Received custom scheme URL: \(url.absoluteString)")
            deepLinkState.handleDeepLink(url, origin: .customScheme, isColdStart: false)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            // Handle Universal Links
            guard let url = userActivity.webpageURL else {
                SpotLogger.warning("SpotApp: Universal link without webpage URL")
                return
            }
            
            let isColdStart = showLaunchScreen
            SpotLogger.info("SpotApp: Received Universal Link: \(url.absoluteString), coldStart: \(isColdStart)")
            deepLinkState.handleDeepLink(url, origin: .universalLink, isColdStart: isColdStart)
        }
    }
}
