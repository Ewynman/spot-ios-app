//
//  EmptyFeedView.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import SwiftUI

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Spots Yet")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)

            Text("Follow people to see their spots!")
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .background(Color(hex: "F5F3EF"))
    }
}
