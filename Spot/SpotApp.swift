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
                }
            }
        }
    }
}
