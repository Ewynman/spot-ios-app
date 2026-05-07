//
//  RootView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var deepLinkState: DeepLinkState
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var showPaywall: Bool = false
    @State private var showPostPurchaseProOnboarding: Bool = false
    @State private var showPostAuthSetup: Bool = false
    @State private var isResolvingPostAuthSetup: Bool = false
    @State private var hasResolvedPostAuthSetup: Bool = false
    @State private var needsTermsUpdateAcceptance: Bool = false
    @State private var pendingActiveTermsVersion: ActiveTermsVersion?
    @State private var hasResolvedTermsAcceptance: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authViewModel.isLoading {
                LaunchView()
            } else if authViewModel.awaitingEmailVerification {
                ConfirmEmailView()
            } else if authViewModel.isAuthenticated {
                Group {
                    if authViewModel.isEmailVerified && hasResolvedPostAuthSetup && showPostAuthSetup {
                        if permissionManager.locationStatus != .authorizedWhenInUse &&
                            permissionManager.locationStatus != .authorizedAlways {
                            LocationPermissionView(authDestination: .postAuthSetup)
                                .environmentObject(permissionManager)
                                .environmentObject(authViewModel)
                        } else if permissionManager.notificationStatus != .authorized {
                            NotificationPermissionView(authDestination: .postAuthSetup)
                                .environmentObject(permissionManager)
                                .environmentObject(authViewModel)
                        } else if permissionManager.photoStatus != .authorized &&
                                    permissionManager.photoStatus != .limited {
                            PhotoPermissionView(authDestination: .postAuthSetup)
                                .environmentObject(permissionManager)
                                .environmentObject(authViewModel)
                        } else if permissionManager.cameraStatus != .authorized {
                            CameraPermissionView(authDestination: .postAuthSetup)
                                .environmentObject(permissionManager)
                                .environmentObject(authViewModel)
                        } else {
                            PostAuthSetupFlowView {
                                showPostAuthSetup = false
                            }
                            .environmentObject(authViewModel)
                            .environmentObject(permissionManager)
                        }
                    } else if authViewModel.isEmailVerified
                                && hasResolvedTermsAcceptance
                                && needsTermsUpdateAcceptance,
                              let activeVersion = pendingActiveTermsVersion {
                        TermsUpdateGateView(activeVersion: activeVersion) {
                            needsTermsUpdateAcceptance = false
                            pendingActiveTermsVersion = nil
                        }
                    } else {
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
                                    source: "deep_link",
                                    mediaPresentation: .detail
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
                    }
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView(onProUnlocked: queuePostPurchaseProOnboardingIfNeeded)
                        .environmentObject(authViewModel)
                }
                .fullScreenCover(isPresented: $showPostPurchaseProOnboarding) {
                    PostPurchaseProOnboardingView {
                        showPostPurchaseProOnboarding = false
                    }
                    .environmentObject(authViewModel)
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
        .onReceive(NotificationCenter.default.publisher(for: .showPostPurchaseProOnboarding)) { _ in
            queuePostPurchaseProOnboardingIfNeeded()
        }
        .task(id: "\(authViewModel.userId ?? "nil")-\(authViewModel.isAuthenticated)-\(authViewModel.isEmailVerified)") {
            hasResolvedPostAuthSetup = false
            hasResolvedTermsAcceptance = false
            await refreshPostAuthSetupRequirement()
            await refreshStoreKitEntitlementIfNeeded()
            await refreshTermsAcceptanceRequirement()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshPostAuthSetupRequirement()
                await refreshStoreKitEntitlementIfNeeded()
                await refreshTermsAcceptanceRequirement()
            }
        }
        .onChange(of: permissionManager.lifecycleRefreshTick) { _, _ in
            Task { await refreshPostAuthSetupRequirement() }
        }
    }

    /// Loads the active Terms version + checks whether the signed-in user has
    /// accepted it. Kept independent of profile/permission setup so a fresh
    /// signup flow doesn't block on a network round-trip we can't satisfy yet.
    @MainActor
    private func refreshTermsAcceptanceRequirement() async {
        guard authViewModel.isAuthenticated, authViewModel.isEmailVerified else {
            hasResolvedTermsAcceptance = true
            needsTermsUpdateAcceptance = false
            pendingActiveTermsVersion = nil
            return
        }

        do {
            async let versionTask = TermsAcceptanceService.shared.loadActiveVersion()
            async let acceptedTask = TermsAcceptanceService.shared.hasAcceptedActiveTerms()
            let version = try await versionTask
            var accepted = (try? await acceptedTask) ?? true

            // If the user agreed via the pre-auth Welcome gate this launch,
            // record the acceptance now and skip the post-auth update gate.
            if !accepted && PreAuthTermsAgreementStore.shared.hasAgreed {
                do {
                    try await TermsAcceptanceService.shared.recordAcceptance()
                    accepted = true
                } catch {
                    // Surface the gate so the user can retry interactively.
                }
            }

            pendingActiveTermsVersion = version
            needsTermsUpdateAcceptance = !accepted
            hasResolvedTermsAcceptance = true

            if accepted {
                pendingActiveTermsVersion = nil
            }
        } catch {
            // Fail-open so a transient network issue can't lock users out
            // of the app entirely. The next foreground refresh will re-check.
            needsTermsUpdateAcceptance = false
            pendingActiveTermsVersion = nil
            hasResolvedTermsAcceptance = true
        }
    }

    private func queuePostPurchaseProOnboardingIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard PostPurchaseProOnboardingManager.shouldShow(userId: authViewModel.userId) else { return }
            showPostPurchaseProOnboarding = true
        }
    }

    @MainActor
    private func refreshStoreKitEntitlementIfNeeded() async {
        guard authViewModel.isAuthenticated,
              authViewModel.isEmailVerified,
              let userId = authViewModel.userId,
              let appAccountToken = UUID(uuidString: userId)
        else { return }

        switch await SubscriptionManager.shared.refreshEntitlement(for: appAccountToken) {
        case .active(let expirationDate):
            await authViewModel.setProActive(true, proUntil: expirationDate)
        case .linkedToDifferentAccount, .inactive:
            await authViewModel.setProActive(false)
        }
    }

    @MainActor
    private func refreshPostAuthSetupRequirement() async {
        isResolvingPostAuthSetup = true
        defer { isResolvingPostAuthSetup = false }

        guard authViewModel.isAuthenticated, authViewModel.isEmailVerified,
              let uidString = authViewModel.userId,
              let uid = UUID(uuidString: uidString)
        else {
            showPostAuthSetup = false
            hasResolvedPostAuthSetup = true
            return
        }

        permissionManager.updatePermissionStatuses()
        let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse ||
            permissionManager.locationStatus == .authorizedAlways
        let notificationsGranted = permissionManager.notificationStatus == .authorized
        let photoGranted = permissionManager.photoStatus == .authorized || permissionManager.photoStatus == .limited
        let cameraGranted = permissionManager.cameraStatus == .authorized

        let session = try? await supabase.auth.session
        let allowProfileCompletionGate = session.map { AuthProfileSetupGate.shouldShowUsernamePhotoPostAuthSetup(session: $0) } ?? false

        struct Row: Decodable {
            let username: String?
            let profile_image_url: String?
        }

        let needsProfileSetup: Bool
        do {
            let row: Row = try await supabase
                .from("users")
                .select("username,profile_image_url")
                .eq("id", value: uid)
                .single()
                .execute()
                .value
            let persistedUsername = row.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let metadataUsername = await bestEffortAuthMetadataUsername()
            let usernameOk = !((persistedUsername?.isEmpty ?? true) && (metadataUsername?.isEmpty ?? true))
            let persistedPhotoURL = row.profile_image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let metadataPhotoURL = await bestEffortAuthMetadataAvatarURL()
            let photoOk = !((persistedPhotoURL?.isEmpty ?? true) && (metadataPhotoURL?.isEmpty ?? true))

            if (persistedPhotoURL?.isEmpty ?? true), let metadataPhotoURL, !metadataPhotoURL.isEmpty {
                struct AvatarPatch: Encodable { let profile_image_url: String }
                _ = try? await supabase
                    .from("users")
                    .update(AvatarPatch(profile_image_url: metadataPhotoURL))
                    .eq("id", value: uid)
                    .execute()
            }
            let profileIncomplete = !(usernameOk && photoOk)
            needsProfileSetup = allowProfileCompletionGate && profileIncomplete
        } catch {
            // Avoid blocking existing users in setup if profile check temporarily fails.
            needsProfileSetup = false
        }

        var shouldShow = (!locationGranted || !notificationsGranted || !photoGranted || !cameraGranted || needsProfileSetup)

        // Guard against transient auth/user-row sync delays right after signup/login:
        // re-check once before presenting profile setup so users with completed profiles
        // never see a brief setup flash.
        if shouldShow && needsProfileSetup && allowProfileCompletionGate {
            try? await Task.sleep(nanoseconds: 350_000_000)
            do {
                let row: Row = try await supabase
                    .from("users")
                    .select("username,profile_image_url")
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value
                let persistedUsername = row.username?.trimmingCharacters(in: .whitespacesAndNewlines)
                let metadataUsername = await bestEffortAuthMetadataUsername()
                let usernameOk = !((persistedUsername?.isEmpty ?? true) && (metadataUsername?.isEmpty ?? true))
                let persistedPhotoURL = row.profile_image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
                let metadataPhotoURL = await bestEffortAuthMetadataAvatarURL()
                let photoOk = !((persistedPhotoURL?.isEmpty ?? true) && (metadataPhotoURL?.isEmpty ?? true))
                let profileIncomplete = !(usernameOk && photoOk)
                let needsProfileAfterRetry = allowProfileCompletionGate && profileIncomplete
                shouldShow = (!locationGranted || !notificationsGranted || !photoGranted || !cameraGranted || needsProfileAfterRetry)
            } catch {
                // Keep the earlier decision on retry errors.
            }
        }

        showPostAuthSetup = shouldShow
        hasResolvedPostAuthSetup = true
    }

    private func bestEffortAuthMetadataAvatarURL() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        let metadata = session.user.userMetadata
        let candidates: [String?] = [
            metadata["profile_image_url"]?.stringValue,
            metadata["avatar_url"]?.stringValue,
            metadata["picture"]?.stringValue
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func bestEffortAuthMetadataUsername() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        let metadata = session.user.userMetadata
        let candidates: [String?] = [
            metadata["username"]?.stringValue,
            metadata["user_name"]?.stringValue,
            metadata["preferred_username"]?.stringValue
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel())
        .environmentObject(DeepLinkState.shared)
        .environmentObject(PermissionManager.shared)
}
