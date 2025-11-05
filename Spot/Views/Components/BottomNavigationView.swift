//
//  BottomNavigationView.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import SwiftUI

struct BottomNavigationView: View {
    @Binding var selectedTab: String

    var body: some View {
        HStack(spacing: 0) {
            Button(action: { selectedTab = "Home" }) {
                BottomNavItem(icon: "house.fill", title: "Home", isSelected: selectedTab == "Home")
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { selectedTab = "Search" }) {
                BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: selectedTab == "Search")
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { selectedTab = "Profile" }) {
                BottomNavItem(icon: "person", title: "Profile", isSelected: selectedTab == "Profile")
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
    }
}

#Preview {
    StatefulPreviewWrapper("Home") { selection in
        VStack {
            Spacer()
            BottomNavigationView(selectedTab: selection)
        }
    }
}

// Helper to preview @Binding
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initialValue: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }
    var body: some View { content($value) }
}

struct BottomNavItem: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? Constants.Colors.primary : .gray)

            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(isSelected ? Constants.Colors.primary : .gray)
        }
        .frame(maxWidth: .infinity)
    }
}
