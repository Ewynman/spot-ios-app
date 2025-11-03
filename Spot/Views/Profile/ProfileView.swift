//
//  ProfileView.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit
import FirebaseFirestore

struct ProfileView: View {
    var userId: String?
    // If true, this screen was pushed from another screen (e.g., Feed/Search).
    // In that case, show a custom back button and hide bottom nav.
    var fromNavigationPush: Bool = false
    @EnvironmentObject var authVM: AuthViewModel
    @State private var username: String? = ""
    @State private var profileImageURL: String?
    @State private var spots: [Spot] = []
    @State private var selectedTab = "Spots"
    @State private var isLoading = true
    @State private var selectedSpot: Spot?
    @State private var pendingDeleteSpot: Spot?
    @State private var showDeleteConfirm: Bool = false
    @State private var deletingSpotIds: Set<String> = []
    @State private var isPrivateProfile: Bool = false
    @State private var isProProfile: Bool = false
    @State private var isFollowingUser: Bool = false
    @State private var hasRequestedFollow: Bool = false
    @State private var canViewContent: Bool = true
    @State private var showMenu: Bool = false
    @State private var showSettingsNav: Bool = false
    @State private var showLikesNav: Bool = false
    @State private var showBookmarksNav: Bool = false
    @State private var showFollowRequestsNav: Bool = false
    @State private var followRequestsCount: Int = 0
    @State private var followReqListener: ListenerRegistration?

    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Spots", "Map"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // MARK: — Top Bar (left-aligned title)
                    HStack(spacing: 0) {
                        let isViewingOther = (userId != nil) && (userId != authVM.userId)
                        if fromNavigationPush || isViewingOther {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Constants.Colors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 8)
                        }

                        Text("Spot")
                            .font(FontManager.logoTitle())
                            .foregroundColor(Constants.Colors.primary)

                        Spacer()

                        if userId == nil || userId == authVM.userId {
                            Button {
                                withAnimation { showMenu.toggle() }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Menu")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Constants.Colors.primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Constants.Colors.primary, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .safeAreaPadding(.top)
                    .padding(.top, 8)

                    // MARK: — Loading State
                    if isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else {
                        // MARK: — Profile Header + Tabs
                        VStack(spacing: 16) {
                            VStack(spacing: 12) {
                                if let url = profileImageURL {
                                    AsyncImage(url: URL(string: url)) { img in
                                        img.resizable()
                                           .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .foregroundColor(.gray)
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.gray)
                                }

                                HStack(spacing: 8) {
                                    Text(username ?? "")
                                        .font(FontManager.sectionHeader())
                                        .foregroundColor(.black)
                                    if isProProfile {
                                        Text("Pro")
                                            .font(.caption)
                                            .foregroundColor(Constants.Colors.buttonText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Constants.Colors.primary)
                                            .cornerRadius(10)
                                    }
                                }

                                Text("\(spots.count) spots shared")
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 12)

                            // Follow / Request actions centered under header when viewing someone else
                            if let viewedUserId = userId, viewedUserId != authVM.userId {
                                VStack {
                                    if isFollowingUser {
                                        Button {
                                            UserSpotService.shared.unfollow(userId: viewedUserId) { result in
                                                DispatchQueue.main.async {
                                                    if case .success = result {
                                                        self.isFollowingUser = false
                                                        self.loadUser(forceReload: true)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Text("Unfollow")
                                                .font(FontManager.primaryText())
                                                .foregroundColor(Constants.Colors.buttonText)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Constants.Colors.primary)
                                                .cornerRadius(20)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    } else if isPrivateProfile {
                                        VStack(spacing: 8) {
                                            Button {
                                                if hasRequestedFollow { return }
                                                UserSpotService.shared.requestFollow(userId: viewedUserId) { result in
                                                    DispatchQueue.main.async {
                                                        if case .success = result {
                                                            self.hasRequestedFollow = true
                                                        }
                                                    }
                                                }
                                            } label: {
                                                Text(hasRequestedFollow ? "Requested" : "Request to Follow")
                                                    .font(FontManager.primaryText())
                                                    .foregroundColor(Constants.Colors.buttonText)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(Constants.Colors.primary)
                                                    .cornerRadius(20)
                                            }
                                            .disabled(hasRequestedFollow)
                                            .buttonStyle(PlainButtonStyle())

                                            if hasRequestedFollow {
                                                Button {
                                                    UserSpotService.shared.cancelFollowRequest(userId: viewedUserId) { result in
                                                        DispatchQueue.main.async {
                                                            if case .success = result {
                                                                self.hasRequestedFollow = false
                                                            }
                                                        }
                                                    }
                                                } label: {
                                                    Text("Cancel Request")
                                                        .font(FontManager.primaryText())
                                                        .foregroundColor(Constants.Colors.primary)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    } else {
                                        Button {
                                            UserSpotService.shared.follow(userId: viewedUserId) { result in
                                                DispatchQueue.main.async {
                                                    if case .success = result { }
                                                }
                                            }
                                        } label: {
                                            Text("Follow")
                                                .font(FontManager.primaryText())
                                                .foregroundColor(Constants.Colors.buttonText)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Constants.Colors.primary)
                                                .cornerRadius(20)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.bottom, 8)
                            }

                            // Tabs (simple text)
                            HStack(spacing: 24) {
                                ForEach(tabs, id: \.self) { tab in
                                    Text(tab)
                                        .font(FontManager.primaryText())
                                        .foregroundColor(selectedTab == tab ? Constants.Colors.primary : .gray)
                                        .fontWeight(.semibold)
                                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }
                                }
                            }

                            if selectedTab == "Spots" {
                                if let selectedSpot {
                                    SpotCard(
                                        spot: selectedSpot,
                                        showUserInfo: false,
                                        userId: userId,
                                        onDelete: { pendingDeleteSpot = selectedSpot; showDeleteConfirm = true },
                                        source: "ProfileInline",
                                        backAction: { withAnimation { self.selectedSpot = nil } }
                                    )
                                    .transition(.opacity)
                                    .zIndex(1)
                                } else {
                                    SpotsGridView(spots: spots) { tapped in
                                        selectedSpot = tapped
                                    }
                                    .zIndex(0)
                                }
                            } else {
                                // Map tab
                                ProfileMapView(spots: spots) { tapped in
                                    selectedSpot = tapped
                                }
                                .zIndex(0)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Custom dropdown overlay
                if showMenu {
                    // Tappable background to dismiss
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showMenu = false } }

                    VStack(alignment: .leading, spacing: 0) {
                        if userId == nil || userId == authVM.userId, !isProProfile {
                            Button {
                                withAnimation { showMenu = false }
                                SpotLogger.info("Open paywall from profile menu")
                                NotificationCenter.default.post(name: .showPaywall, object: nil)
                            } label: {
                                HStack {
                                    Image(systemName: "star.fill")
                                    Text("Go Pro")
                                        .font(FontManager.primaryText())
                                }
                                .foregroundColor(Constants.Colors.primary)
                                .padding(12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                        }
                        Button {
                            withAnimation { showMenu = false }
                            showLikesNav = true
                        } label: {
                            HStack {
                                Image(systemName: "heart.fill")
                                Text("Your Likes")
                                    .font(FontManager.primaryText())
                            }
                            .foregroundColor(Constants.Colors.primary)
                            .padding(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()

                        Button {
                            withAnimation { showMenu = false }
                            showBookmarksNav = true
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                Text("Your Bookmarks")
                                    .font(FontManager.primaryText())
                            }
                            .foregroundColor(Constants.Colors.primary)
                            .padding(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()

                        if isPrivateProfile {
                            Button {
                                withAnimation { showMenu = false }
                                showFollowRequestsNav = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("Follow Requests")
                                        .font(FontManager.primaryText())
                                    if followRequestsCount > 0 {
                                        Text("\(followRequestsCount)")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Constants.Colors.primary)
                                            .foregroundColor(Constants.Colors.buttonText)
                                            .cornerRadius(8)
                                    }
                                }
                                .foregroundColor(Constants.Colors.primary)
                                .padding(12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                        }

                        Button {
                            withAnimation { showMenu = false }
                            showSettingsNav = true
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Settings")
                                    .font(FontManager.primaryText())
                            }
                            .foregroundColor(Constants.Colors.primary)
                            .padding(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Constants.Colors.primary, lineWidth: 1)
                    )
                    .frame(width: UIScreen.main.bounds.width * 0.5)
                    .padding(.trailing, 16)
                    .padding(.top, 44)
                }
            }
            .background(Constants.Colors.background.ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // Only load if we haven't loaded this user yet
                if lastLoadedUserId != userId {
                    loadUser()
                }
                // Start/stop pending count listener for own private profile
                let isSelf = (userId == nil) || (userId == authVM.userId)
                if isSelf && isPrivateProfile, let uid = authVM.userId {
                    followReqListener?.remove()
                    followReqListener = FollowRequestsService.shared.listenPendingCount(for: uid) { n in
                        followRequestsCount = n
                    }
                }
            }
            .onDisappear { followReqListener?.remove(); followReqListener = nil }
            .navigationDestination(isPresented: $showSettingsNav) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showLikesNav) {
                SpotGridScreen(context: .likes, userId: userId)
            }
            .navigationDestination(isPresented: $showBookmarksNav) {
                SpotGridScreen(context: .bookmarks, userId: userId)
            }
            .navigationDestination(isPresented: $showFollowRequestsNav) {
                FollowRequestsView()
            }
            .alert("Delete this spot? This can’t be undone.", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let spot = pendingDeleteSpot { Task { await deleteSpotFromProfile(spot) } }
                }
                Button("Cancel", role: .cancel) { pendingDeleteSpot = nil }
            }
        }
    }

    @State private var isLoadingUser = false
    @State private var lastLoadedUserId: String?

    private func loadUser(forceReload: Bool = false) {
        // Prevent multiple concurrent calls
        guard !isLoadingUser else { return }

        // Prevent reloading the same user unless forced
        if !forceReload, let lastLoaded = lastLoadedUserId, lastLoaded == userId {
            return
        }

        isLoadingUser = true
        isLoading = true

        Task {
            do {
                let data = try await ProfileService.fetchProfile(for: userId)
                await MainActor.run {
                    username = data.username
                    profileImageURL = data.profileImageURL
                    spots = data.spots
                    isPrivateProfile = data.isPrivate
                    isProProfile = data.isPro
                    isFollowingUser = data.isFollowing
                    hasRequestedFollow = data.hasRequested
                    canViewContent = data.canView
                    lastLoadedUserId = userId
                    isLoading = false
                    isLoadingUser = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isLoadingUser = false
                }
                SpotLogger.error("Profile loadUser failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Deletion helpers
extension ProfileView {
    @MainActor
    private func deleteSpotFromProfile(_ spot: Spot) async {
        guard let id = spot.id else { return }
        if deletingSpotIds.contains(id) { return }
        deletingSpotIds.insert(id)

        let prevSpots = spots
        spots.removeAll { $0.id == id }

        do {
            try await SpotService.shared.deleteSpot(spot)
            deletingSpotIds.remove(id)
        } catch {
            SpotLogger.error("Profile delete failed: \(error.localizedDescription)")
            spots = prevSpots
            deletingSpotIds.remove(id)
        }
    }
}
