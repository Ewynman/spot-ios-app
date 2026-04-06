//
//  BottomTabNavigationView.swift
//  Spot
//
//  Created By Wynman, Edward (Current date)
//

import SwiftUI

/// Dedicated Post tab: wraps the full post flow. On success, notifies so Feed can refresh.
private struct PostTabView: View {
    var body: some View {
        PostFlowView(onPostSuccess: { _ in
            NotificationCenter.default.post(name: .spotDidPostSuccess, object: nil)
        })
    }
}

struct BottomTabNavigationView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
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
                    PostTabView()
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
                Button(action: { selectedTab = 0 }) {
                    BottomNavItem(icon: "house.fill", title: "Home", isSelected: selectedTab == 0)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { selectedTab = 1 }) {
                    BottomNavItem(icon: "map.fill", title: "Map", isSelected: selectedTab == 1)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { selectedTab = 2 }) {
                    BottomNavItem(icon: "plus.square.fill", title: "Post", isSelected: selectedTab == 2)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { selectedTab = 3 }) {
                    BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: selectedTab == 3)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { selectedTab = 4 }) {
                    BottomNavItem(icon: "person.fill", title: "Profile", isSelected: selectedTab == 4)
                }
                .buttonStyle(PlainButtonStyle())
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
            .ignoresSafeArea(.keyboard)
        }
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
