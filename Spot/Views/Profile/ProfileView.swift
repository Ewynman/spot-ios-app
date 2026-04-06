//
//  ProfileView.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit

struct ProfileView: View {
    var userId: String?
    var fromNavigationPush: Bool = false
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedTab = "Spots"
    @State private var selectedSpot: Spot?
    @State private var pendingDeleteSpot: Spot?
    @State private var showDeleteConfirm: Bool = false
    @State private var showMenu: Bool = false
    @State private var showSettingsNav: Bool = false
    @State private var showLikesNav: Bool = false
    @State private var showBookmarksNav: Bool = false
    @State private var showFollowRequestsNav: Bool = false
    @State private var isMapExpanded: Bool = false

    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Spots", "Map"]

    var body: some View {
        let content = profileContent
        
        if fromNavigationPush {
            // Already in parent NavigationStack, don't wrap
            content
        } else {
            // Root view, wrap in NavigationStack
            NavigationStack {
                content
            }
        }
    }
    
    private var profileContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // MARK: — Top Bar (left-aligned title)
                HStack(spacing: 0) {
                    let isViewingOther = (userId != nil) && (userId != authVM.userId)
                    
                    // Always show back button when viewing other user's profile or when navigated from another screen
                    if fromNavigationPush || isViewingOther {
                        Button {
                            if selectedSpot != nil {
                                // If spot is selected, go back to profile first
                                withAnimation { self.selectedSpot = nil }
                            } else {
                                // Otherwise, dismiss the entire profile view
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 8)
                    } else if selectedSpot != nil {
                        // Show back button when spot is expanded (own profile)
                        Button {
                            withAnimation { self.selectedSpot = nil }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Constants.Colors.primary)
                                Text("Back to profile")
                                    .font(FontManager.primaryText())
                                    .foregroundColor(Constants.Colors.primary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if selectedSpot == nil {
                        Text("Spot")
                            .font(FontManager.logoTitle())
                            .foregroundColor(Constants.Colors.primary)
                    }

                    Spacer()

                    if selectedSpot == nil && (userId == nil || userId == authVM.userId) {
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
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    // MARK: — Profile Header + Tabs
                    VStack(spacing: 16) {
                        // Collapsed header when spot is selected on map, full header otherwise
                        if selectedSpot == nil && !(selectedTab == "Map" && isMapExpanded) {
                            // Full header
                            VStack(spacing: 12) {
                                if let urlString = viewModel.profileImageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                                    RemoteImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        case .failure(let failure):
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                                .onAppear {
                                                    SpotLogger.error("Profile image failed to load", details: [
                                                        "url": urlString,
                                                        "statusCode": failure.statusCode as Any,
                                                        "error": failure.underlying.localizedDescription
                                                    ])
                                                }
                                        case .empty:
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                        @unknown default:
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                        }
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
                                    Text(viewModel.username ?? "")
                                        .font(FontManager.sectionHeader())
                                        .foregroundColor(.black)
                                    if (userId == nil || userId == authVM.userId) ? authVM.isPro : viewModel.isProProfile {
                                        Text("Pro")
                                            .font(.caption)
                                            .foregroundColor(Constants.Colors.buttonText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Constants.Colors.primary)
                                            .cornerRadius(10)
                                    }
                                }

                                Text("\(viewModel.spots.count) spots shared")
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 12)
                        } else if selectedSpot != nil && selectedTab == "Map" {
                            // Collapsed header when spot is selected on map
                            HStack(spacing: 12) {
                                if let urlString = viewModel.profileImageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                                    RemoteImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        case .failure(let failure):
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                                .onAppear {
                                                    SpotLogger.error("Profile image failed to load", details: [
                                                        "url": urlString,
                                                        "statusCode": failure.statusCode as Any,
                                                        "error": failure.underlying.localizedDescription
                                                    ])
                                                }
                                        case .empty:
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                        @unknown default:
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .foregroundColor(.gray)
                                }
                                
                                Text(viewModel.username ?? "")
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.black)
                                
                                if (userId == nil || userId == authVM.userId) ? authVM.isPro : viewModel.isProProfile {
                                    Text("Pro")
                                        .font(.caption2)
                                        .foregroundColor(Constants.Colors.buttonText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Constants.Colors.primary)
                                        .cornerRadius(8)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        // Follow / Request actions centered under header when viewing someone else
                        if let viewedUserId = userId, viewedUserId != authVM.userId {
                            VStack {
                                if viewModel.isFollowingUser {
                                    Button {
                                        viewModel.unfollow(targetUserId: viewedUserId)
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
                                } else if viewModel.isPrivateProfile {
                                    VStack(spacing: 8) {
                                        Button {
                                            if viewModel.hasRequestedFollow { return }
                                            viewModel.requestFollow(targetUserId: viewedUserId)
                                        } label: {
                                            Text(viewModel.hasRequestedFollow ? "Requested" : "Request to Follow")
                                                .font(FontManager.primaryText())
                                                .foregroundColor(Constants.Colors.buttonText)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Constants.Colors.primary)
                                                .cornerRadius(20)
                                        }
                                        .disabled(viewModel.hasRequestedFollow)
                                        .buttonStyle(PlainButtonStyle())

                                        if viewModel.hasRequestedFollow {
                                            Button {
                                                viewModel.cancelFollowRequest(targetUserId: viewedUserId)
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
                                        viewModel.follow(targetUserId: viewedUserId)
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

                        // Tabs (simple text) - always visible
                        HStack(spacing: 24) {
                            ForEach(tabs, id: \.self) { tab in
                                Text(tab)
                                    .font(FontManager.primaryText())
                                    .foregroundColor(selectedTab == tab ? Constants.Colors.primary : .gray)
                                    .fontWeight(.semibold)
                                    .onTapGesture { 
                                        withAnimation(.easeInOut(duration: 0.2)) { 
                                            selectedTab = tab
                                            // Clear selected spot when switching tabs
                                            if selectedSpot != nil {
                                                selectedSpot = nil
                                            }
                                        } 
                                    }
                            }
                        }
                        .padding(.top, selectedSpot != nil && selectedTab == "Map" ? 8 : 0)

                        if selectedTab == "Spots" {
                            if let selectedSpot {
                                SpotCard(
                                    spot: selectedSpot,
                                    showUserInfo: false,
                                    userId: userId,
                                    onDelete: { pendingDeleteSpot = selectedSpot; showDeleteConfirm = true },
                                    source: "ProfileInline"
                                    // backAction removed - now handled by ProfileView top bar
                                )
                                .transition(.opacity)
                                .zIndex(1)
                            } else {
                                SpotsGridView(spots: viewModel.spots) { tapped in
                                    selectedSpot = tapped
                                }
                                .zIndex(0)
                            }
                        } else {
                            // Map tab
                            ProfileMapView(spots: viewModel.spots, onSpotTap: { tapped in
                                selectedSpot = tapped
                            }, onCollapseChange: { expanded in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { isMapExpanded = expanded }
                            })
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
                    if userId == nil || userId == authVM.userId, !viewModel.isProProfile {
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

                    if viewModel.isPrivateProfile {
                        Button {
                            withAnimation { showMenu = false }
                            showFollowRequestsNav = true
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Follow Requests")
                                    .font(FontManager.primaryText())
                                if viewModel.followRequestsCount > 0 {
                                    Text("\(viewModel.followRequestsCount)")
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
            Task { await viewModel.loadUser(userId: userId) }
            let isSelf = (userId == nil) || (userId == authVM.userId)
            if isSelf && viewModel.isPrivateProfile {
                viewModel.startFollowRequestsListener(ownUserId: authVM.userId)
            }
        }
        .onChange(of: showSettingsNav) { _, isShowing in
            if !isShowing {
                Task { await viewModel.loadUser(userId: userId, forceReload: true) }
            }
        }
        .onDisappear {
            viewModel.stopFollowRequestsListener()
            Task { @MainActor in
                selectedSpot = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        .navigationDestination(isPresented: $showSettingsNav) {
            SettingsView()
        }
        .navigationDestination(isPresented: $showLikesNav) {
            SpotGridScreen(context: .likes, userId: userId)
        }
        .navigationDestination(isPresented: $showBookmarksNav) {
            if authVM.isPro {
                BookmarksCollectionsScreen()
                    .environmentObject(authVM)
            } else {
                SpotGridScreen(context: .bookmarks, userId: userId)
            }
        }
        .navigationDestination(isPresented: $showFollowRequestsNav) {
            FollowRequestsView()
        }
        .alert("Delete this spot? This can't be undone.", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let spot = pendingDeleteSpot { Task { await viewModel.deleteSpot(spot) } }
                pendingDeleteSpot = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSpot = nil }
        }
        .onChange(of: authVM.isPro) { _, newValue in
            if userId == nil || userId == authVM.userId {
                viewModel.isProProfile = newValue
            }
        }
    }
}

#Preview {
    let auth = AuthViewModel()
    auth.isPro = true
    return ProfileView(userId: nil, fromNavigationPush: false)
        .environmentObject(auth)
}
