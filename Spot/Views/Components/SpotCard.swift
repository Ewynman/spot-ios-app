// SpotCard.swift
// Spot
//
// Created by Edward Wynman on 8/6/25.
//

import SwiftUI

struct SpotCard: View {
    let spot: Spot
    let showUserInfo: Bool    // show profile pic + username if true
    let userId: String?
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    @State private var isLoadingLike = false
    @State private var isLoadingSave = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    init(spot: Spot, showUserInfo: Bool = true, userId: String? = nil) {
        self.spot = spot
        self.showUserInfo = showUserInfo
        self.userId = userId
        self._isLiked = State(initialValue: spot.isLiked ?? false)
        self._isSaved = State(initialValue: spot.isSaved ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: — Header: Username (optional) + Location
            HStack {
                if showUserInfo, let userId = spot.userId {
                    NavigationLink {
                        ProfileView(userId: userId)
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        HStack(spacing: 8) {
                            // Profile Image
                            if let urlString = spot.userProfileImageURL,
                               let url = URL(string: urlString)
                            {
                                AsyncImage(url: url) { img in
                                    img.resizable()
                                       .scaledToFill()
                                       .frame(width: 32, height: 32)
                                       .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Constants.Colors.background)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(Constants.Colors.primary)
                                        )
                                }
                            } else {
                                Circle()
                                    .fill(Constants.Colors.background)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Constants.Colors.primary)
                                    )
                            }

                            Text(spot.username ?? "")
                                .font(FontManager.primaryText())
                                .fontWeight(.semibold)
                                .foregroundColor(Constants.Colors.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                if let location = spot.locationName, !location.isEmpty {
                    Text(location)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal, 12)

            // MARK: — Spot Image
            if let urlString = spot.imageURL,
               let url = URL(string: urlString)
            {
                AsyncImage(url: url) { img in
                    img.resizable()
                       .aspectRatio(contentMode: .fit)
                       .frame(maxWidth: .infinity, maxHeight: 400)
                       .clipped()
                       .cornerRadius(12)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .overlay(
                            ProgressView()
                                .foregroundColor(Constants.Colors.primary)
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Constants.Colors.background)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(Constants.Colors.primary)
                    )
            }

            // MARK: — Interaction Bar
            HStack {
                HStack(spacing: 16) {
                    Button {
                        guard !isLoadingLike, let spotId = spot.id, let userId = userId else { return }
                        let prev = isLiked
                        isLiked.toggle()
                        isLoadingLike = true
                        if isLiked {
                            UserSpotService.shared.likeSpot(spotId: spotId) { result in
                                isLoadingLike = false
                                if case .failure(_) = result {
                                    isLiked = prev
                                    showError = true
                                    errorMessage = "Failed to like. Please try again."
                                }
                            }
                        } else {
                            UserSpotService.shared.unlikeSpot(spotId: spotId) { result in
                                isLoadingLike = false
                                if case .failure(_) = result {
                                    isLiked = prev
                                    showError = true
                                    errorMessage = "Failed to unlike. Please try again."
                                }
                            }
                        }
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 22))
                            .foregroundColor(isLiked ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        guard !isLoadingSave, let spotId = spot.id, let userId = userId else { return }
                        let prev = isSaved
                        isSaved.toggle()
                        isLoadingSave = true
                        if isSaved {
                            UserSpotService.shared.bookmarkSpot(spotId: spotId) { result in
                                isLoadingSave = false
                                if case .failure(_) = result {
                                    isSaved = prev
                                    showError = true
                                    errorMessage = "Failed to bookmark. Please try again."
                                }
                            }
                        } else {
                            UserSpotService.shared.unbookmarkSpot(spotId: spotId) { result in
                                isLoadingSave = false
                                if case .failure(_) = result {
                                    isSaved = prev
                                    showError = true
                                    errorMessage = "Failed to unbookmark. Please try again."
                                }
                            }
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22))
                            .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                if let vibe = spot.vibeTag, !vibe.isEmpty {
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
            .padding(.bottom, 10)

            if showError {
                Text(errorMessage)
                    .font(FontManager.primaryText())
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Constants.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
