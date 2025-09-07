//
//  SpotDetailView.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit

struct SpotDetailView: View {
    let spot: Spot
    let isMapView: Bool // true if opened from map, false if opened from grid
    var sourceContext: SpotGridContext? // Context for back button text
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var cameraPosition: MapCameraPosition
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    @State private var isLoadingLike: Bool = false
    @State private var isLoadingSave: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false

    private var backButtonText: String {
        if let sourceContext = sourceContext {
            switch sourceContext {
            case .likes:
                return "Back to All Likes"
            case .bookmarks:
                return "Back to All Bookmarks"
            }
        } else if isMapView {
            return "Back to Map"
        } else {
            return "Back to All Spots"
        }
    }

    init(spot: Spot, isMapView: Bool, sourceContext: SpotGridContext? = nil, onDismiss: (() -> Void)? = nil) {
        self.spot = spot
        self.isMapView = isMapView
        self.sourceContext = sourceContext
        self.onDismiss = onDismiss

        if let lat = spot.latitude, let long = spot.longitude {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: long),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        } else {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        }

        _isLiked = State(initialValue: spot.isLiked ?? false)
        _isSaved = State(initialValue: spot.isSaved ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button(action: {
                    // Log back button tap
                    if let sourceContext = sourceContext {
                        switch sourceContext {
                        case .likes:
                            SpotLogger.info("Analytics: back_from_spot_detail_context=likes")
                        case .bookmarks:
                            SpotLogger.info("Analytics: back_from_spot_detail_context=bookmarks")
                        }
                    }

                    onDismiss?()
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(backButtonText)
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isMapView {
                HStack(spacing: 12) {
                    if let profileImageURL = spot.userProfileImageURL {
                        AsyncImage(url: URL(string: profileImageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }

                    Text(spot.username ?? "")
                        .font(FontManager.primaryText())
                        .fontWeight(.semibold)

                    Spacer()

                    if let locationName = spot.locationName {
                        Text(locationName)
                            .font(FontManager.primaryText())
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            ScrollView {
                VStack(spacing: 0) {
                    // Spot Image
                    if let imageURL = spot.imageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(contentMode: .fit)
                        }
                    }

                    // Interaction bar
                    HStack {
                        HStack(spacing: 16) {
                            Button(action: {
                                guard !isLoadingLike, let spotId = spot.id, authVM.userId != nil else { return }
                                isLiked.toggle()
                                isLoadingLike = true
                                if isLiked {
                                    authVM.likeSpot(spotId)
                                    isLoadingLike = false
                                } else {
                                    authVM.unlikeSpot(spotId)
                                    isLoadingLike = false
                                }
                            }) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .foregroundColor(isLiked ? .red : .gray)
                                    .font(.system(size: 22))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                guard !isLoadingSave, let spotId = spot.id, authVM.userId != nil else { return }
                                isSaved.toggle()
                                isLoadingSave = true
                                if isSaved {
                                    authVM.bookmarkSpot(spotId)
                                    isLoadingSave = false
                                } else {
                                    authVM.unbookmarkSpot(spotId)
                                    isLoadingSave = false
                                }
                            }) {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                                    .font(.system(size: 22))
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Owner-only overflow menu next to bookmark
                            let current = authVM.userId ?? ""
                            let owner = spot.userId ?? ""
                            if !current.isEmpty && current == owner {
                                Button {
                                    SpotLogger.debug("Overflow tapped (detail) id=\(spot.id ?? "nil")")
                                    showDeleteConfirm = true
                                } label: {
                                    Text("⋮")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Constants.Colors.primary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isDeleting)
                            }
                        }

                        Spacer()

                        if let vibe = spot.vibeTag {
                            Text(vibe)
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Constants.Colors.accent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Location name for grid
                    if !isMapView, let locationName = spot.locationName {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(Constants.Colors.primary)
                            Text(locationName)
                                .font(FontManager.primaryText())
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
            }

            if isMapView {
                Map(position: $cameraPosition) {
                    if let lat = spot.latitude, let lon = spot.longitude {
                        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        Annotation("", coordinate: coord) {
                            Image("green_marker")
                                .resizable()
                                .frame(width: 40, height: 40)
                        }
                    }
                }
                .preferredColorScheme(.light)
                .frame(height: 200)
            }
        }
        .background(Color(hex: "F5F3EF"))
        .navigationBarBackButtonHidden(true)
        .alert("Delete this spot? This can’t be undone.", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteSpot() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Delete
extension SpotDetailView {
    @MainActor
    private func deleteSpot() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        guard let _ = spot.id else {
            SpotLogger.error("SpotDetailView: delete requested but spot.id is nil")
            return
        }
        do {
            try await SpotService.shared.deleteSpot(spot)
            // Dismiss and let parent refresh/remove
            onDismiss?()
        } catch {
            SpotLogger.error("SpotDetailView: delete failed: \(error.localizedDescription)")
        }
    }
}
