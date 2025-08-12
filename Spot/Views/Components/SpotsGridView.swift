// SpotsGridView.swift
// Spot
//
// Created by Edward Wynman on 8/6/25.
//

import SwiftUI

struct SpotsGridView: View {
    let spots: [Spot]
    let onSpotTapped: (Spot) -> Void
    var onLoadMore: (() -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(spots) { spot in
                    Button {
                        onSpotTapped(spot)
                    } label: {
                        SpotGridItem(spot: spot)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            if let onLoadMore {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            // Prefetch when bottom sentinel appears
                            onLoadMore()
                        }
                }
                .frame(height: 1)
            }
        }
    }
}

struct SpotGridItem: View {
    let spot: Spot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL = spot.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { img in
                    img.resizable()
                       .scaledToFill()
                       .frame(
                         width: UIScreen.main.bounds.width / 2 - 18,
                         height: 160
                       )
                       .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 160)
                }
            }

            if let location = spot.locationName {
                Text(location)
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Constants.Colors.primary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
