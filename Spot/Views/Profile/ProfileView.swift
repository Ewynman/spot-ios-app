// ProfileView.swift
// Spot
//
// Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit

struct ProfileView: View {
    var userId: String? = nil
    @EnvironmentObject var authVM: AuthViewModel
    @State private var username: String? = ""
    @State private var profileImageURL: String?
    @State private var spots: [Spot] = []
    @State private var selectedTab = "Spots"
    @State private var isLoading = true
    @State private var selectedSpot: Spot?
    @State private var isPrivateProfile: Bool = false
    @State private var isFollowingUser: Bool = false
    @State private var hasRequestedFollow: Bool = false
    @State private var canViewContent: Bool = true
    @State private var showMenu: Bool = false
    @State private var showSettingsNav: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Spots", "Map"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                // MARK: — Top Bar
                HStack {
                    if let viewedUserId = userId, viewedUserId != authVM.userId {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Text("Spot")
                        .font(FontManager.logoTitle())
                        .foregroundColor(Constants.Colors.primary)
                        .frame(maxWidth: .infinity)

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

                            Text(username ?? "")
                                .font(FontManager.sectionHeader())
                                .foregroundColor(.black)

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
                                                    self.loadUser()
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
                                                if case .success = result {
                                                    self.isFollowingUser = true
                                                    self.canViewContent = true
                                                    self.loadUser()
                                                }
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
                            .frame(maxWidth: .infinity)
                        }

                        HStack(spacing: 32) {
                            ForEach(tabs, id: \.self) { tab in
                                VStack(spacing: 4) {
                                    Text(tab)
                                        .font(FontManager.primaryText())
                                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                                        .foregroundColor(selectedTab == tab ? Constants.Colors.primary : .gray)
                                    Rectangle()
                                        .fill(selectedTab == tab ? Constants.Colors.primary : Color.clear)
                                        .frame(height: 2)
                                }
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTab = tab
                                        selectedSpot = nil
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)

                    // MARK: — Main Content
                    if !canViewContent {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                            Text("This user is private")
                                .font(FontManager.primaryText())
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedTab == "Spots" {
                        if let spot = selectedSpot {
                            // -------------------------
                            // Show just the tapped SpotCard
                            // -------------------------
                            ScrollView {
                                HStack {
                                    Button {
                                        withAnimation(.easeInOut) {
                                            selectedSpot = nil
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "chevron.left")
                                            Text("Back to Spots")
                                        }
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)

                                SpotCard(spot: spot, showUserInfo: false, userId: authVM.userId)
                                    .padding(.vertical, 12)
                            }
                        } else {
                            // -------------------------
                            // Show the grid of spots
                            // -------------------------
                            SpotsGridView(spots: spots) { tapped in
                                withAnimation(.easeInOut) {
                                    selectedSpot = tapped
                                }
                            }
                        }
                    } else {
                        // Map tab unchanged
                        ProfileMapView(spots: spots) { tapped in
                            selectedSpot = tapped
                        }
                    }
                }

                // Optional bottom nav if viewing someone else's profile
                if userId != authVM.userId {
                    BottomNavigationView(selectedTab: .constant("Home"))
                }
                }

                // Custom dropdown overlay
                if showMenu {
                    // Tappable background to dismiss
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showMenu = false } }

                    VStack(alignment: .leading, spacing: 0) {
                        Button { /* Likes */ withAnimation { showMenu = false } } label: {
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

                        Button { /* Bookmarks */ withAnimation { showMenu = false } } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                Text("Bookmarks")
                                    .font(FontManager.primaryText())
                            }
                            .foregroundColor(Constants.Colors.primary)
                            .padding(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()

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
            .background(Color(hex: "F5F3EF"))
            .navigationBarBackButtonHidden(true)
            .onAppear { loadUser() }
            .navigationDestination(isPresented: $showSettingsNav) {
                SettingsView()
            }
        }
    }

    private func loadUser() {
        isLoading = true
        Task {
            do {
                let data = try await ProfileService.fetchProfile(for: userId)
                await MainActor.run {
                    username = data.username
                    profileImageURL = data.profileImageURL
                    spots = data.spots
                    isPrivateProfile = data.isPrivate
                    isFollowingUser = data.isFollowing
                    hasRequestedFollow = data.hasRequested
                    canViewContent = data.canView
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
