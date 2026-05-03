//
//  BottomTabNavigationView.swift
//  Spot
//
//  Created By Wynman, Edward (Current date)
//

import SwiftUI

/// Dedicated Post tab: wraps the full post flow. After queueing a publish, switches to Home; completion toast comes from `SpotPublishCoordinator` + feed refresh on `.spotDidPostSuccess`.
private struct PostTabView: View {
    @Binding var selectedTab: Int

    var body: some View {
        PostFlowView(onPostQueued: { selectedTab = 0 })
    }
}

private struct PublishBannerView: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView()
                .progressViewStyle(.linear)
                .tint(Constants.Colors.primary)
                .scaleEffect(x: 1, y: 0.8, anchor: .center)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Constants.Colors.primary.opacity(0.12))
                        .frame(height: 4)
                        .offset(y: 1)
                )
                .clipShape(Capsule())
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 4)
                }
                .frame(height: 8)
            }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Constants.Colors.background)
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct BottomTabNavigationView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var spotPublishCoordinator = SpotPublishCoordinator.shared
    @StateObject private var firstRunOnboarding = SpotFirstRunOnboardingManager()
    @State private var selectedTab: Int = 0
    @State private var coachFrames: [CoachTarget: CGRect] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Page content for selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        HomepageView()
                    case 1:
                        MapView(spots: [])
                            .environmentObject(authVM)
                    case 2:
                        PostTabView(selectedTab: $selectedTab)
                    case 3:
                        SearchView()
                            .environmentObject(authVM)
                    case 4:
                        ProfileView(userId: nil, fromNavigationPush: false)
                            .environmentObject(authVM)
                    default:
                        HomepageView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Custom bottom bar (same design as before: built into page, not system tab bar)
                HStack(spacing: 0) {
                    Button(action: { selectTab(0) }) {
                        BottomNavItem(icon: "house.fill", title: "Home", isSelected: selectedTab == 0)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("navigation.homeTab")

                    Button(action: { selectTab(1) }) {
                        BottomNavItem(icon: "map.fill", title: "Map", isSelected: selectedTab == 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .measure(target: .mapTab)
                    .accessibilityIdentifier("navigation.mapTab")

                    Button(action: { selectTab(2) }) {
                        BottomNavItem(icon: "plus.square.fill", title: "Post", isSelected: selectedTab == 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("navigation.postTab")

                    Button(action: { selectTab(3) }) {
                        BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: selectedTab == 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("navigation.searchTab")

                    Button(action: { selectTab(4) }) {
                        BottomNavItem(icon: "person.fill", title: "Profile", isSelected: selectedTab == 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("navigation.profileTab")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Constants.Colors.background)
                .overlay(
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1),
                    alignment: .top
                )
            }
            .ignoresSafeArea(.keyboard)

            VStack(spacing: 8) {
                if spotPublishCoordinator.bannerPhase != .hidden {
                    PublishBannerView(title: spotPublishCoordinator.bannerTitle)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if spotPublishCoordinator.showToast {
                    ToastView(message: spotPublishCoordinator.toastMessage, isError: spotPublishCoordinator.toastIsError)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: spotPublishCoordinator.bannerPhase)
            .animation(.easeInOut(duration: 0.2), value: spotPublishCoordinator.showToast)

            SpotFirstRunOnboardingOverlay(
                manager: firstRunOnboarding,
                targetRect: currentTourTargetRect,
                onPrimary: handleOnboardingPrimaryAction,
                onBack: handleOnboardingBack,
                onSkip: firstRunOnboarding.skip
            )
        }
        .onPreferenceChange(CoachFramesPrefKey.self) { coachFrames = $0 }
        .onAppear(perform: evaluateFirstRunOnboarding)
        .onChange(of: authVM.isAuthenticated) { _, _ in evaluateFirstRunOnboarding() }
        .onChange(of: authVM.userId) { _, _ in evaluateFirstRunOnboarding() }
        .onChange(of: authVM.likedSpots) { _, _ in evaluateFirstRunOnboarding() }
        .onChange(of: authVM.bookmarkedSpots) { _, _ in evaluateFirstRunOnboarding() }
        .accessibilityIdentifier("main.tabShell")
    }

    private var currentTourTargetRect: CGRect? {
        guard let target = firstRunOnboarding.currentStep.target else { return nil }
        return coachFrames[target]
    }

    private func selectTab(_ tab: Int) {
        selectedTab = tab
        if tab == 1 {
            firstRunOnboarding.mapTabSelected()
        }
    }

    private func evaluateFirstRunOnboarding() {
        let firstSessionCandidate = authVM.likedSpots.isEmpty && authVM.bookmarkedSpots.isEmpty
        // Only force Home during the active welcome overlay. `currentStep` defaults to
        // `.welcome` and stays that way for users who completed onboarding via migration
        // without advancing steps; pairing with `isPresented` avoids jumping Home on
        // every `likedSpots` / `bookmarkedSpots` change (e.g. liking from Map or Search).
        if selectedTab != 0, firstRunOnboarding.isPresented, firstRunOnboarding.currentStep == .welcome {
            selectedTab = 0
        }
        firstRunOnboarding.startIfNeeded(
            isAuthenticated: authVM.isAuthenticated,
            isFirstSessionCandidate: firstSessionCandidate,
            userId: authVM.userId
        )
    }

    private func handleOnboardingPrimaryAction() {
        switch firstRunOnboarding.currentStep {
        case .welcome:
            selectedTab = 0
            // Let the home feed begin loading so the first `SpotCard` can publish
            // coach geometry before the tour highlights the card step.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                firstRunOnboarding.startTour()
            }
        case .mapTab:
            selectedTab = 1
            firstRunOnboarding.mapTabSelected()
        case .finale:
            selectedTab = 0
            firstRunOnboarding.finish()
        default:
            firstRunOnboarding.next()
        }
    }

    private func handleOnboardingBack() {
        if firstRunOnboarding.currentStep == .mapTab {
            selectedTab = 0
        }
        firstRunOnboarding.back()
    }
}

// MARK: - Previews

#Preview("Bottom tab navigation") {
    let auth = AuthViewModel()
    auth.isAuthenticated = true
    return BottomTabNavigationView()
        .environmentObject(auth)
}

#Preview("Tab bar only") {
    struct TabBarOnlyPreview: View {
        @State private var selected: Int = 0
        var body: some View {
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { idx in
                        Button(action: { selected = idx }) {
                            BottomNavItem(
                                icon: ["house.fill", "map.fill", "plus.square.fill", "magnifyingglass", "person.fill"][idx],
                                title: ["Home", "Map", "Post", "Search", "Profile"][idx],
                                isSelected: selected == idx
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Constants.Colors.background)
                .overlay(
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1),
                    alignment: .top
                )
            }
        }
    }
    return TabBarOnlyPreview()
}
