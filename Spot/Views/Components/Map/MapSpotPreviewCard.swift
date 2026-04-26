//
//  MapSpotPreviewCard.swift
//  Spot
//
//  Map-safe wrapper around `SpotCard`. Solves the IMG_9741 bug where the
//  selected card could overflow the screen and force the map to shift
//  awkwardly. The wrapper:
//
//   * computes a clamped panel height from actual screen geometry
//     (`MapPanelHeight.clamp`),
//   * scrolls internally if `SpotCard` content exceeds available height,
//   * pads bottom for the home indicator,
//   * paints `Constants.Colors.background` and stays under the safe area
//     for the home indicator without leaving an unstyled gap.
//
//  The preview card always shows the *full* `SpotCard`. Eddie's call:
//  user wants the entire spot card surface, not a slim preview. The
//  scroll-on-overflow is what keeps small devices safe.
//

import SwiftUI

struct MapSpotPreviewCard: View {
    let spot: Spot
    /// Optional override that lets the discovery map hide the delete
    /// button while the profile map keeps it.
    var allowDelete: Bool = false
    /// Source label propagated to `SpotCard` analytics.
    var source: String
    /// Shown only on the profile map: a "back to all spots" affordance.
    var onBackToAll: (() -> Void)?
    /// Required: closes the preview panel.
    var onClose: () -> Void
    /// Optional delete handler (profile-owner only).
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                SpotCard(
                    spot: spot,
                    showUserInfo: true,
                    userId: nil,
                    onDelete: { onDelete?() },
                    source: source
                )
                .padding(.horizontal, Constants.Layout.Spacing.large)
                .padding(.bottom, Constants.Layout.Spacing.extraLarge)
            }
        }
        .background(
            Constants.Colors.background
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Spot preview"))
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                if let onBackToAll {
                    Button(action: onBackToAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back to all spots")
                                .font(FontManager.buttonText())
                        }
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Constants.Colors.primary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Constants.Layout.Spacing.large)
        }
        .frame(height: 36)
        .padding(.top, 6)
    }
}

// MARK: - Previews

#Preview("Map preview – discovery") {
    let sample = Spot(
        id: "preview-discovery",
        userId: "u1",
        username: "eddie",
        userProfileImageURL: nil,
        imageURL: "https://picsum.photos/seed/spot1/800/600",
        thumbnailURL: nil,
        vibeTag: "Hidden Gem",
        latitude: 40.7128,
        longitude: -74.0060,
        locationName: "New York, NY",
        likes: 12,
        isLiked: false,
        isSaved: false,
        createdAt: Date(),
        authorIsPrivate: false
    )
    let auth = AuthViewModel()
    return MapSpotPreviewCard(
        spot: sample,
        source: "MapPreview",
        onClose: {}
    )
    .environmentObject(auth)
    .frame(maxWidth: .infinity, maxHeight: 380)
    .background(Constants.Colors.background)
}

#Preview("Map preview – profile w/ back") {
    let sample = Spot(
        id: "preview-profile",
        userId: "u1",
        username: "eddie",
        userProfileImageURL: nil,
        imageURL: "https://picsum.photos/seed/spot2/800/600",
        thumbnailURL: nil,
        vibeTag: "Sunset View",
        latitude: 25.7617,
        longitude: -80.1918,
        locationName: "Miami Beach",
        likes: 5,
        isLiked: true,
        isSaved: false,
        createdAt: Date(),
        authorIsPrivate: false
    )
    let auth = AuthViewModel()
    return MapSpotPreviewCard(
        spot: sample,
        allowDelete: true,
        source: "ProfileMapPreview",
        onBackToAll: {},
        onClose: {},
        onDelete: {}
    )
    .environmentObject(auth)
    .frame(maxWidth: .infinity, maxHeight: 320)
    .background(Constants.Colors.background)
}

#Preview("Map preview – constrained height") {
    let sample = Spot(
        id: "preview-tight",
        userId: "u1",
        username: "eddie",
        userProfileImageURL: nil,
        imageURL: "https://picsum.photos/seed/spot3/800/600",
        thumbnailURL: nil,
        vibeTag: "Romantic",
        latitude: 25.7617,
        longitude: -80.1918,
        locationName: "Bayfront",
        likes: 220,
        isLiked: false,
        isSaved: true,
        createdAt: Date()
    )
    let auth = AuthViewModel()
    return MapSpotPreviewCard(
        spot: sample,
        source: "MapPreviewTight",
        onClose: {}
    )
    .environmentObject(auth)
    // Tight frame mirrors the IMG_9741 scenario.
    .frame(maxWidth: .infinity, maxHeight: 220)
    .background(Constants.Colors.background)
}
