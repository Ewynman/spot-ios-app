// SpotCard.swift
// Spot
//
// Created by Edward Wynman on 8/6/25.
//

import SwiftUI

// MARK: - Preference Keys

struct MenuButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct SpotCard: View {
    let spot: Spot
    let showUserInfo: Bool    // show profile pic + username if true
    let userId: String?
    var onDelete: (() -> Void)? = nil
    var source: String = "Unknown"
    @State private var showDeleteConfirm: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showReportSheet: Bool = false
    @State private var showCustomMenu: Bool = false
    @State private var menuButtonFrame: CGRect = .zero
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isLiked: Bool = false
    @State private var isSaved: Bool = false
    @State private var isLoadingLike = false
    @State private var isLoadingSave = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    init(spot: Spot, showUserInfo: Bool = true, userId: String? = nil, onDelete: (() -> Void)? = nil, source: String = "Unknown") {
        self.spot = spot
        self.showUserInfo = showUserInfo
        self.userId = userId
        self.onDelete = onDelete
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: — Header: Username (optional) + Location
            HStack {
                if showUserInfo, let userId = spot.userId {
                    NavigationLink {
                        ProfileView(userId: userId, fromNavigationPush: true)
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
                                .measure(target: .username)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                if let location = spot.locationName, !location.isEmpty {
                    Text(location)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                        .measure(target: .location)
                }
            }
            .padding(.horizontal, 12)

            // MARK: — Spot Image
            if let thumb = spot.thumbnailURL, let turl = URL(string: thumb) {
                AsyncImage(url: turl) { th in
                    th.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .clipped()
                        .cornerRadius(12)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                }
                .overlay(
                    Group {
                        if let full = spot.imageURL, let furl = URL(string: full) {
                            AsyncImage(url: furl) { img in
                                img.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: 400)
                                    .clipped()
                                    .cornerRadius(12)
                                    .onAppear {
                                        if let tFirst = PerfMetrics.shared.measure("t_first_item") {
                                            PerfMetrics.shared.recordOnce("img_first_paint", value: tFirst)
                                        }
                                    }
                            } placeholder: {
                                // Keep showing the thumbnail
                                Color.clear
                            }
                        }
                    }
                )
            } else if let urlString = spot.imageURL, let url = URL(string: urlString) {
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
                            authVM.likeSpot(spotId)
                            isLoadingLike = false
                        } else {
                            authVM.unlikeSpot(spotId)
                            isLoadingLike = false
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
                            authVM.bookmarkSpot(spotId)
                            isLoadingSave = false
                        } else {
                            authVM.unbookmarkSpot(spotId)
                            isLoadingSave = false
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22))
                            .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Owner-only overflow menu, placed next to bookmark
                    let currentUserId = userId ?? authVM.userId ?? ""
                    let ownerId = spot.userId ?? ""
                    let isOwner = (!currentUserId.isEmpty && !ownerId.isEmpty && currentUserId == ownerId)
                    // Three-dot menu for all spots
                    Button {
                        SpotLogger.debug("Menu tapped for spot id=\(spot.id ?? "nil") [\(source)]")
                        showCustomMenu = true
                    } label: {
                        Text("⋮")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Constants.Colors.primary)
                            .frame(width: 24, height: 24, alignment: .center)
                            .contentShape(Rectangle())
                            .accessibilityLabel("More actions")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: MenuButtonFrameKey.self, value: geo.frame(in: .global))
                                }
                            )
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
                        .measure(target: .vibeTag)
                }

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .overlay(
                GeometryReader { geo in
                    let likeArea = CGRect(x: 16, y: 0, width: 80, height: geo.size.height)
                    Color.clear.preference(key: CoachFramesPrefKey.self, value: [.likeSave: geo.frame(in: .global).intersection(CGRect(origin: geo.frame(in: .global).origin, size: likeArea.size))])
                }
            )

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
        .onAppear {
            isLiked = authVM.likedSpots.contains(spot.id ?? "")
            isSaved = authVM.bookmarkedSpots.contains(spot.id ?? "")
            let currentUserId = userId ?? authVM.userId ?? ""
            let ownerId = spot.userId ?? ""
            let isOwner = (!currentUserId.isEmpty && !ownerId.isEmpty && currentUserId == ownerId)
            SpotLogger.debug("SpotCard appear [\(source)]: id=\(spot.id ?? "nil"), owner=\(ownerId.isEmpty ? "nil" : ownerId), current=\(currentUserId.isEmpty ? "nil" : currentUserId), isOwner=\(isOwner)")
            if currentUserId.isEmpty || ownerId.isEmpty {
                SpotLogger.warning("SpotCard owner-gate inputs missing [\(source)] id=\(spot.id ?? "nil")")
            }
        }
        .alert("Delete this spot? This can't be undone.", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(
            // Custom dropdown menu overlay
            Group {
                if showCustomMenu {
                    customMenuOverlay
                }
            }
        )
        .onPreferenceChange(MenuButtonFrameKey.self) { frame in
            menuButtonFrame = frame
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(spot: spot)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(spot: spot)
        }
    }
    
    // MARK: - Custom Menu
    private var customMenuOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                // Tappable background to dismiss
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showCustomMenu = false }
                
                // Position menu near the three dots button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        customMenuContent
                            .padding(.trailing, 16)
                            .padding(.bottom, 8)
                    }
                }
                .offset(x: -menuButtonFrame.width - 8, y: -menuButtonFrame.height - 8)
            }
        }
    }
    
    private var customMenuContent: some View {
        let currentUserId = userId ?? authVM.userId ?? ""
        let ownerId = spot.userId ?? ""
        let isOwner = (!currentUserId.isEmpty && !ownerId.isEmpty && currentUserId == ownerId)
        
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                showCustomMenu = false
                SpotLogger.debug("Share tapped for spot id=\(spot.id ?? "nil") [\(source)]")
                showShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                        .font(FontManager.primaryText())
                }
                .foregroundColor(Constants.Colors.primary)
                .padding(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            if !isOwner {
                Divider()
                
                Button {
                    showCustomMenu = false
                    SpotLogger.debug("Report tapped for spot id=\(spot.id ?? "nil") [\(source)]")
                    showReportSheet = true
                } label: {
                    HStack {
                        Image(systemName: "flag")
                        Text("Report")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                    .padding(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                
                Button {
                    showCustomMenu = false
                    if let targetUserId = spot.userId {
                        Task {
                            do {
                                try await authVM.blockUser(userId: targetUserId)
                                SpotLogger.info("User blocked from spot menu: \(targetUserId)")
                            } catch {
                                SpotLogger.error("Failed to block user: \(error.localizedDescription)")
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "circle.slash")
                        Text("Block User")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                    .padding(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if isOwner, onDelete != nil {
                Divider()
                
                Button {
                    showCustomMenu = false
                    SpotLogger.debug("Delete tapped for spot id=\(spot.id ?? "nil") [\(source)]")
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(.red)
                    .padding(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Constants.Colors.primary, lineWidth: 1)
        )
        .frame(width: 150)
    }
}
