import SwiftUI
import FirebaseFirestore

struct BookmarksCollectionsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var collections: [BookmarkCollection] = []
    @State private var isLoading: Bool = true
    @State private var previews: [String: [String]] = [:] // collectionId -> imageURLs (up to 4)
    @State private var allPreviewURLs: [String] = []
    @State private var navigateToAll: Bool = false
    @State private var selectedCollection: BookmarkCollection?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text("Your Bookmarks")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                Spacer()

                // balance spacer
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        // All Bookmarks card
                        Button { navigateToAll = true } label: {
                            CollectionCardView(
                                title: "All Bookmarks",
                                previewURLs: allPreviewURLs,
                                count: nil
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        ForEach(collections) { c in
                            Button { selectedCollection = c } label: {
                                CollectionCardView(
                                    title: c.name,
                                    previewURLs: previews[c.id] ?? [],
                                    count: c.spotIds.count
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.background.ignoresSafeArea())
        .navigationDestination(isPresented: $navigateToAll) {
            SpotGridScreen(context: .bookmarks, userId: authVM.userId)
        }
        .sheet(item: $selectedCollection) { collection in
            NavigationStack {
                CollectionDetailScreen(collection: collection, onBack: { selectedCollection = nil })
            }
        }
        .onAppear { Task { await load() } }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func load() async {
        isLoading = true
        do {
            let cols = try await BookmarksCollectionsService.shared.listCollections()
            collections = cols
            await loadPreviews()
        } catch {
            collections = []
        }
        isLoading = false
    }

    private func loadPreviews() async {
        // All bookmarks preview: up to first 4 saved
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UserSpotService.shared.fetchUserSpotLists { _, bookmarked in
                Task {
                    let urls = await fetchSpotPreviewURLs(spotIds: Array(bookmarked.prefix(4)))
                    allPreviewURLs = urls
                    cont.resume()
                }
            }
        }

        // Per collection previews: first spot id
        await withTaskGroup(of: (String, [String]).self) { group in
            for c in collections {
                let ids = Array(c.spotIds.prefix(4))
                group.addTask {
                    let urls = await fetchSpotPreviewURLs(spotIds: ids)
                    return (c.id, urls)
                }
            }
            for await (cid, urls) in group {
                previews[cid] = urls
            }
        }
    }

    private func fetchSpotPreviewURLs(spotIds: [String], limit: Int = 4) async -> [String] {
        guard !spotIds.isEmpty else { return [] }
        let spotsRef = Firestore.firestore().collection("spots")
        var urls: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for id in spotIds.prefix(limit) {
                group.addTask {
                    do {
                        let doc = try await spotsRef.document(id).getDocument()
                        guard doc.exists else { return nil }
                        let data = doc.data() ?? [:]
                        if let thumb = data["thumbnailURL"] as? String, !thumb.isEmpty { return thumb }
                        if let arr = data["imageURLs"] as? [String], let first = arr.first { return first }
                        if let single = data["imageURL"] as? String { return single }
                        return nil
                    } catch {
                        return nil
                    }
                }
            }
            for await maybe in group {
                if let u = maybe { urls.append(u) }
            }
        }
        return Array(urls.prefix(limit))
    }
}

private struct CollectionDetailScreen: View {
    let collection: BookmarkCollection
    var onBack: () -> Void
    @State private var spots: [Spot] = []
    @State private var isLoading: Bool = true
    @State private var selectedSpot: Spot?

    var body: some View {
        VStack(spacing: 0) {
            // Header - always visible
            HStack {
                Button {
                    if selectedSpot != nil {
                        withAnimation { selectedSpot = nil }
                    } else {
                        onBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text(collection.name)
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                Spacer()
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Content
            if isLoading {
                Spacer(); ProgressView(); Spacer()
            } else if spots.isEmpty {
                Spacer()
                Text("No spots in this collection yet")
                    .font(FontManager.primaryText())
                    .foregroundColor(.gray)
                Spacer()
            } else {
                if let selectedSpot {
                    // Show expanded spot - header stays visible
                    ScrollView {
                        SpotCard(
                            spot: selectedSpot,
                            showUserInfo: false,
                            userId: nil,
                            onDelete: nil,
                            source: "CollectionDetail",
                            backAction: nil // Don't show back button, header handles it
                        )
                        .padding(.top, 8)
                    }
                    .transition(.opacity)
                } else {
                    // Grid content
                    SpotsGridView(
                        spots: spots,
                        onSpotTapped: { spot in
                            withAnimation {
                                selectedSpot = spot
                            }
                        },
                        columns: 3
                    )
                    .refreshable { await load() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.background.ignoresSafeArea())
        .onAppear { Task { await load() } }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func load() async {
        isLoading = true
        do {
            let ids = collection.spotIds
            var results: [Spot] = []
            let spotsRef = Firestore.firestore().collection("spots")
            for id in ids {
                do {
                    let doc = try await spotsRef.document(id).getDocument()
                    if let spot = try? doc.data(as: Spot.self) { results.append(spot) }
                } catch { }
            }
            // Sort by createdAt desc
            results.sort { (a, b) in
                (a.createdAt ?? Date.distantPast) > (b.createdAt ?? Date.distantPast)
            }
            spots = results
        }
        isLoading = false
    }
}

#Preview {
    let auth = AuthViewModel()
    auth.isPro = true
    return BookmarksCollectionsScreen().environmentObject(auth)
}
