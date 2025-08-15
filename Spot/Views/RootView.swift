//
//  RootView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @EnvironmentObject var deepLinkState: DeepLinkState

    var body: some View {
        Group {
            if authViewModel.isLoading {
                LaunchView()
            } else if authViewModel.isAuthenticated {
                HomepageView()
                    .sheet(isPresented: $deepLinkState.isLoadingSpot) {
                        SpotLoadingView()
                    }
                    .sheet(isPresented: $deepLinkState.isNavigatingToSpot) {
                        if let spot = deepLinkState.spotDetailSpot {
                            SpotDetailView(spot: spot, isMapView: false) {
                                deepLinkState.dismissSpotDetail()
                            }
                        }
                    }
                    .sheet(isPresented: $deepLinkState.showSpotUnavailable) {
                        SpotUnavailableView {
                            deepLinkState.dismissSpotUnavailable()
                        }
                    }
                    .onAppear {
                        // Process any pending deep links when user becomes authenticated
                        deepLinkState.processPendingDeepLinks()
                    }
            } else {
                WelcomeView()
            }
        }
        .environmentObject(authViewModel)
    }
}

#Preview {
    RootView()
}
