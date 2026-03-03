//
//  FeedMapTabBarView.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import SwiftUI

struct FeedMapTabBarView: View {
    @Binding var selectedFeedView: String
    let tabs: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 32) {
                ForEach(tabs, id: \.self) { tab in
                    VStack(spacing: 4) {
                        Text(tab)
                            .font(FontManager.primaryText())
                            .fontWeight(selectedFeedView == tab ? .semibold : .regular)
                            .foregroundColor(selectedFeedView == tab ? Constants.Colors.primary : .gray)
                        Rectangle()
                            .fill(selectedFeedView == tab ? Constants.Colors.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedFeedView = tab }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}
