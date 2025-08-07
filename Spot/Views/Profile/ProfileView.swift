// ProfileView.swift
// Spot
//
// Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit

struct ProfileView: View {
    var userId: String? = nil
    @State private var username: String? = ""
    @State private var profileImageURL: String?
    @State private var spots: [Spot] = []
    @State private var selectedTab = "Spots"
    @State private var isLoading = true
    @State private var selectedSpot: Spot?
    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Spots", "Map"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: — Top Bar
                HStack {
                    if userId != nil {
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

                    if userId == nil {
                        Menu {
                            Button { } label: { Label("Your Likes", systemImage: "heart.fill") }
                            Button { } label: { Label("Bookmarks", systemImage: "bookmark.fill") }
                            Button { } label: { Label("Settings", systemImage: "gearshape.fill") }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20))
                                .foregroundColor(Constants.Colors.primary)
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
                    if selectedTab == "Spots" {
                        Group {
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

                                    SpotCard(spot: spot, showUserInfo: false)
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
                        }
                    } else {
                        // Map tab unchanged
                        ProfileMapView(spots: spots) { tapped in
                            selectedSpot = tapped
                        }
                    }
                }

                // Optional bottom nav if viewing someone else's profile
                if userId != nil {
                    BottomNavigationView(selectedTab: .constant("Home"))
                }
            }
            .background(Color(hex: "F5F3EF"))
            .onAppear { loadUser() }
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
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
