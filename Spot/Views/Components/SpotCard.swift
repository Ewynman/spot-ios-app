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

#Preview {
    let sample = Spot(
        id: "s1",
        userId: "u1",
        username: "eddie",
        userProfileImageURL: nil,
        imageURL: "https://picsum.photos/seed/spot1/800/600",
        thumbnailURL: nil,
        vibeTag: "Fishing",
        latitude: 40.7128,
        longitude: -74.0060,
        locationName: "New York, NY",
        likes: 0,
        isLiked: false,
        isSaved: false,
        createdAt: Date(),
        authorIsPrivate: false,
        imageURLs: [
            "https://picsum.photos/seed/spot1a/800/600",
            "https://picsum.photos/seed/spot1b/800/600"
        ]
    )
    let auth = AuthViewModel()
    auth.isPro = true
    return SpotCard(spot: sample, showUserInfo: true, userId: "u1", onDelete: {}, source: "Preview")
        .environmentObject(auth)
        .padding()
        .background(Color(hex: "F5F3EF"))
}

struct SpotCard: View {
    let spot: Spot
    let showUserInfo: Bool    // show profile pic + username if true
    let userId: String?
    var onDelete: (() -> Void)?
    var source: String = "Unknown"
    var backAction: (() -> Void)?
    var onImageFailure: ((Spot) -> Void)?
    var onImageRetry: ((Spot) -> Void)?
    @State private var showDeleteConfirm: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showReportSheet: Bool = false
    @State private var showCollectionPicker: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showCustomMenu: Bool = false
    @State private var menuButtonFrame: CGRect = .zero
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isLiked: Bool = false
    @State private var isSaved: Bool = false
    @State private var isLoadingLike = false
    @State private var isLoadingSave = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var thumbnailFailed: Bool = false
    @State private var reportedImageFailure: Bool = false
    @State private var retryToken: UUID = UUID()

    init(spot: Spot, showUserInfo: Bool = true, userId: String? = nil, onDelete: (() -> Void)? = nil, source: String = "Unknown", backAction: (() -> Void)? = nil, onImageFailure: ((Spot) -> Void)? = nil, onImageRetry: ((Spot) -> Void)? = nil) {
        self.spot = spot
        self.showUserInfo = showUserInfo
        self.userId = userId
        self.onDelete = onDelete
        self.source = source
        self.backAction = backAction
        self.onImageFailure = onImageFailure
        self.onImageRetry = onImageRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            spotImage
            interactionBar
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
            SpotLogger.debug("SpotCard appear", details: [
                "source": source,
                "spotId": spot.id ?? "nil",
                "ownerId": ownerId.isEmpty ? "nil" : ownerId,
                "currentUserId": currentUserId.isEmpty ? "nil" : currentUserId,
                "isOwner": isOwner
            ])
            if currentUserId.isEmpty || ownerId.isEmpty {
                SpotLogger.warning("SpotCard owner-gate inputs missing", details: ["source": source, "spotId": spot.id ?? "nil"])
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
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerSheet(spotId: spot.id ?? "") { showCollectionPicker = false }
        }
        .sheet(isPresented: $showEditSheet) {
            EditSpotView(spot: spot) { _ in }
                .environmentObject(authVM)
        }
    }

    // MARK: - Split sections to help type-checker
    @ViewBuilder private var header: some View {
        HStack {
            if let backAction {
                Button { backAction() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Constants.Colors.primary)
                        Text("Back to all spots")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else if showUserInfo, let userId = spot.userId {
                NavigationLink {
                    ProfileView(userId: userId, fromNavigationPush: true)
                        .navigationBarBackButtonHidden(true)
                } label: {
                    HStack(spacing: 8) {
                        if let urlString = spot.userProfileImageURL,
                           let url = URL(string: urlString) {
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
    }

    @ViewBuilder private var spotImage: some View {
        if let urls = spot.imageURLs, !urls.isEmpty {
            SpotImageGallery(urls: urls, fallback: spot.imageURL)
        } else if let thumb = spot.thumbnailURL, let turl = URL(string: thumb) {
            AsyncImage(url: turl, transaction: Transaction(animation: .default)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                case .success(let image):
                    image.resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipped()
                        .cornerRadius(12)
                case .failure:
                    Image("image_placeholder")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipped()
                        .cornerRadius(12)
                        .onAppear {
                            let host = URL(string: thumb)?.host ?? "unknown"
                            SpotLogger.error("Image.Thumb.Failure", details: [
                                "spotId": spot.id ?? "nil",
                                "source": source,
                                "thumbHost": host,
                                "thumbUrl": thumb
                            ])
                            thumbnailFailed = true
                            if !reportedImageFailure {
                                reportedImageFailure = true
                                onImageFailure?(spot)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                retryToken = UUID(); onImageRetry?(spot)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(FontManager.primaryText())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(8)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                }
            }
            .id(retryToken)
            .overlay(fullImageOverlay)
        } else if let urlString = spot.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                case .success(let image):
                    image.resizable()
                       .scaledToFill()
                       .frame(maxWidth: .infinity)
                       .frame(height: 320)
                       .clipped()
                       .cornerRadius(12)
                        .onAppear {
                            SpotLogger.info("Spot image loaded", details: [
                                "spotId": spot.id ?? "nil",
                                "source": source,
                                "hasThumb": false,
                                "url": urlString
                            ])
                        }
                case .failure:
                    Image("image_placeholder")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipped()
                        .cornerRadius(12)
                        .onAppear {
                            let host = url.host ?? "unknown"
                            SpotLogger.error("Image.Full.Failure", details: [
                                "spotId": spot.id ?? "nil",
                                "source": source,
                                "fullHost": host,
                                "fullUrl": urlString
                            ])
                            if !reportedImageFailure {
                                reportedImageFailure = true
                                onImageFailure?(spot)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button { retryToken = UUID(); onImageRetry?(spot) } label: {
                                HStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text("Retry") }
                                    .font(FontManager.primaryText())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(8)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.background)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                }
            }
            .id(retryToken)
        } else {
            Image("image_placeholder")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()
                .cornerRadius(12)
                .onAppear {
                    SpotLogger.error("Image placeholder used", details: [
                        "spotId": spot.id ?? "nil",
                        "source": source,
                        "hasThumb": false,
                        "url": spot.imageURL ?? "nil"
                    ])
                }
        }
    }

    private var fullImageOverlay: some View {
        Group {
            if let full = spot.imageURL, let furl = URL(string: full), spot.imageURLs?.isEmpty ?? true {
                AsyncImage(url: furl, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .clipped()
                            .cornerRadius(12)
                            .onAppear {
                                if let tFirst = PerfMetrics.shared.measure("t_first_item") {
                                    PerfMetrics.shared.recordOnce("img_first_paint", value: tFirst)
                                }
                                SpotLogger.info("Spot image loaded", details: [
                                    "spotId": spot.id ?? "nil",
                                    "source": source,
                                    "hasThumb": true,
                                    "url": full
                                ])
                            }
                    case .failure:
                        Color.clear.onAppear {
                            let host = URL(string: full)?.host ?? "unknown"
                            SpotLogger.error("Image.Full.Failure", details: [
                                "spotId": spot.id ?? "nil",
                                "source": source,
                                "fullHost": host,
                                "fullUrl": full
                            ])
                            if !reportedImageFailure {
                                reportedImageFailure = true
                                onImageFailure?(spot)
                            }
                        }
                    @unknown default:
                        Color.clear
                    }
                }
                .id(retryToken)
            }
        }
    }

    private var interactionBar: some View {
        // let _ is to be userId done to supress warnings
        HStack {
            HStack(spacing: 16) {
                Button {
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
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(isLiked ? .red : .gray)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    guard !isLoadingSave, let spotId = spot.id, authVM.userId != nil else { return }
                    if !isSaved, !authVM.isPro, authVM.bookmarkedSpots.count >= 50 {
                        NotificationCenter.default.post(name: .showPaywall, object: nil)
                        return
                    }
                    isSaved.toggle()
                    isLoadingSave = true
                    if isSaved {
                        authVM.bookmarkSpot(spotId)
                        isLoadingSave = false
                        // Pro: immediately allow adding to a collection (Instagram-style)
                        if authVM.isPro { showCollectionPicker = true }
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

                Button {
                    SpotLogger.debug("Menu tapped", details: ["spotId": spot.id ?? "nil", "source": source])
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
    }

    // MARK: - Custom Menu
    private var customMenuOverlay: some View {
        GeometryReader { _ in
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
                SpotLogger.debug("Share tapped", details: ["spotId": spot.id ?? "nil", "source": source])
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

            Divider()

            Button {
                showCustomMenu = false
                if authVM.isPro { showCollectionPicker = true } else { NotificationCenter.default.post(name: .showPaywall, object: nil) }
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Add to Collection")
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
                    SpotLogger.debug("Report tapped", details: ["spotId": spot.id ?? "nil", "source": source])
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
                                SpotLogger.info("User blocked from spot menu", details: ["targetUserId": targetUserId])
                            } catch {
                                SpotLogger.error("Failed to block user", details: ["error": error.localizedDescription])
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
                    if authVM.isPro { showEditSheet = true } else { NotificationCenter.default.post(name: .showPaywall, object: nil) }
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                    .padding(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    showCustomMenu = false
                    SpotLogger.debug("Delete tapped", details: ["spotId": spot.id ?? "nil", "source": source])
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

    // MARK: - Collection Picker Sheet
    private struct CollectionPickerSheet: View {
        let spotId: String
        var onDone: () -> Void
        @State private var collections: [BookmarkCollection] = []
        @State private var newName: String = ""
        @State private var isLoading: Bool = true

        var body: some View {
            NavigationStack {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView().padding(.top, 16)
                    } else {
                        List {
                            ForEach(collections) { c in
                                Button {
                                    Task { await add(to: c.id) }
                                } label: {
                                    HStack {
                                        Text(c.name)
                                            .font(FontManager.primaryText())
                                            .foregroundColor(Constants.Colors.primary)
                                        Spacer()
                                        Text("\(c.spotIds.count)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .listStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        TextField("New collection", text: $newName)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Constants.Colors.primary, lineWidth: 1))
                        Button {
                            Task { await create() }
                        } label: {
                            Text("Create")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Constants.Colors.primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 8)
                .background(Constants.Colors.background)
                .navigationTitle("Add to Collection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") { onDone() }
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
                .onAppear { Task { await load() } }
            }
        }

        private func load() async {
            isLoading = true
            do { collections = try await BookmarksCollectionsService.shared.listCollections() } catch { collections = [] }
            isLoading = false
        }

        private func create() async {
            let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            do {
                _ = try await BookmarksCollectionsService.shared.createCollection(name: name)
                newName = ""
                await load()
            } catch { }
        }

        private func add(to collectionId: String) async {
            guard !spotId.isEmpty else { return }
            do {
                try await BookmarksCollectionsService.shared.addSpot(spotId, to: collectionId)
                onDone()
            } catch { }
        }
    }
}
