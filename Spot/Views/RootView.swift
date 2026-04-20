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
    @State private var showPaywall: Bool = false

    var body: some View {
        Group {
            if authViewModel.isLoading {
                LaunchView()
            } else if authViewModel.awaitingEmailVerification {
                ConfirmEmailView()
            } else if authViewModel.isAuthenticated {
                ZStack {
                    // Main content (verified vs confirm)
                    Group {
                        if authViewModel.isEmailVerified {
                            MainTabView()
                        } else {
                            ConfirmEmailView()
                        }
                    }
                    // Shared Spot Overlay
                    if deepLinkState.isNavigatingToSpot, let spot = deepLinkState.spotDetailSpot {
                        VStack(spacing: 0) {
                            // Top Navigation Bar
                            HStack {
                                Button(action: {
                                    deepLinkState.dismissSpotDetail()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("Back")
                                            .font(FontManager.primaryText())
                                    }
                                    .foregroundColor(Constants.Colors.primary)
                                }
                                .buttonStyle(PlainButtonStyle())

                                Spacer()

                                Text("Shared Spot")
                                    .font(FontManager.sectionHeader())
                                    .fontWeight(.bold)
                                    .foregroundColor(Constants.Colors.primary)

                                Spacer()

                                // Invisible button for balance
                                Button(action: {}) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("Back")
                                            .font(FontManager.primaryText())
                                    }
                                    .foregroundColor(.clear)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                            // Spot Card
                            ScrollView {
                                SpotCard(
                                    spot: spot,
                                    showUserInfo: true,
                                    userId: spot.userId,
                                    source: "deep_link"
                                )
                                .padding(.horizontal, 16)
                                .padding(.bottom, 32)
                            }
                        }
                        .background(Color(hex: "F5F3EF"))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: deepLinkState.isNavigatingToSpot)
                    }

                    // Loading Overlay
                    if deepLinkState.isLoadingSpot {
                        VStack {
                            Spacer()
                            SpotLoadingView()
                            Spacer()
                        }
                        .background(Color(hex: "F5F3EF").opacity(0.9))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: deepLinkState.isLoadingSpot)
                    }

                    // Spot Unavailable Overlay
                    if deepLinkState.showSpotUnavailable {
                        VStack {
                            Spacer()
                            SpotUnavailableView {
                                deepLinkState.dismissSpotUnavailable()
                            }
                            Spacer()
                        }
                        .background(Color(hex: "F5F3EF").opacity(0.9))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: deepLinkState.showSpotUnavailable)
                    }
                    
                    // Subscription Success Overlay
                    if deepLinkState.showSubscriptionSuccess {
                        VStack {
                            Spacer()
                            ProSuccessView()
                                .environmentObject(authViewModel)
                                .environmentObject(deepLinkState)
                            Spacer()
                        }
                        .background(Color(hex: "F5F3EF").opacity(0.9))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: deepLinkState.showSubscriptionSuccess)
                        .onAppear {
                            // Refresh pro status when showing success screen (async fetch runs inside refreshUserFlags)
                            authViewModel.refreshUserFlags()
                        }
                    }
                }
                .onAppear {
                    // Process any pending deep links when user becomes authenticated
                    deepLinkState.processPendingDeepLinks()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView().environmentObject(authViewModel)
                }
            } else {
                WelcomeView()
            }
        }
        .environmentObject(authViewModel)
        .onOpenURL { url in
            // Handle custom scheme URLs
            SpotLogger.log(RootViewLogs.receivedCustomSchemeUrl, details: ["url": url.absoluteString])
            deepLinkState.handleDeepLink(url, origin: .customScheme, isColdStart: false)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            // Handle Universal Links
            guard let url = userActivity.webpageURL else {
                SpotLogger.log(RootViewLogs.universalLinkWithoutWebpageUrl)
                return
            }

            SpotLogger.log(RootViewLogs.receivedUniversalLink, details: ["url": url.absoluteString])
            deepLinkState.handleDeepLink(url, origin: .universalLink, isColdStart: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPaywall)) { _ in
            showPaywall = true
        }
    }
}

#Preview {
    RootView()
}
