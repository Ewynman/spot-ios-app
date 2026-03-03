import SwiftUI
import MapKit
import FirebaseFirestore // Added for DocumentSnapshot
import FirebaseAuth

class FeedViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var mapSpots: [Spot] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var deletingSpotIds: Set<String> = []
    private var loadTask: Task<Void, Never>?
    private let repo = FeedRepository.shared

    deinit {
        loadTask?.cancel()
    }

    func loadInitialSpots() async {
        loadTask?.cancel()
        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadInitial()
            await MainActor.run {
                self.spots = repo.spots
                self.hasMore = repo.moreAvailable
                self.isLoading = false
            }
        }
    }

    func loadMoreSpots() {
        guard !isLoading, hasMore else { return }

        // Cancel any existing task
        loadTask?.cancel()

        // Start new loading task
        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadMore()
            await MainActor.run {
                let new = repo.spots
                self.spots = new
                self.hasMore = repo.moreAvailable
                self.isLoading = false
            }
        }
    }

    func refreshFeed() async {
        // Cancel any existing task
        loadTask?.cancel()

        // Start new refresh task
        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadInitial()
            await MainActor.run {
                self.spots = repo.spots
                self.hasMore = repo.moreAvailable
                self.isLoading = false
            }
        }
        // Wait for the task to complete
        await loadTask?.value
    }
    
    // MARK: - Insert newly posted spot
    @MainActor
    func insertNewSpot(_ spot: Spot) {
        // Remove if already exists (shouldn't happen, but safety check)
        spots.removeAll { $0.id == spot.id }
        // Insert at the beginning
        spots.insert(spot, at: 0)
        SpotLogger.info("Inserted new spot at top of feed", details: ["spotId": spot.safeId])
    }

    func loadMapSpots(forceRefresh: Bool = false) {
        // No-op: Map now loads by viewport; keep an empty set here
        SpotLogger.debug("Map spots warm disabled; viewport loader handles fetching", details: [:])
        self.mapSpots = []
    }

    // MARK: - Delete
    @MainActor
    func delete(spot: Spot) async {
        guard let id = spot.id else {
            SpotLogger.error("Delete requested for spot without id", details: [:])
            return
        }
        if deletingSpotIds.contains(id) { return }
        deletingSpotIds.insert(id)

        // Optimistic removal
        let prevSpots = spots
        let prevMap = mapSpots
        spots.removeAll { $0.id == id }
        mapSpots.removeAll { $0.id == id }

        do {
            SpotLogger.info("Deleting spot", details: ["spotId": id])
            // Run deletion off main
            try await SpotService.shared.deleteSpot(spot)
            deletingSpotIds.remove(id)
            // Force refresh map spots after successful deletion
            loadMapSpots(forceRefresh: true)
        } catch {
            SpotLogger.error("Delete failed", details: ["spotId": id, "error": error.localizedDescription])
            // Rollback
            spots = prevSpots
            mapSpots = prevMap
            deletingSpotIds.remove(id)
        }
    }
}

struct HomepageView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var feedVM = FeedViewModel()
    @State private var showVerifyToast = false
    @State private var showPostSuccessToast = false
    // Tour
    @StateObject private var tourManager = HomeTourManager()
    var isFirstSessionAfterSignup: Bool { authVM.isAuthenticated && (authVM.likedSpots.isEmpty && authVM.bookmarkedSpots.isEmpty) && !tourManager.hasSeenHomeTour }
    @State private var coachFrames: [CoachTarget: CGRect] = [:]

    var body: some View {
        NavigationStack {
            HomeTourHost(manager: tourManager, coachFrames: $coachFrames, isFirstSessionAfterSignup: isFirstSessionAfterSignup) {
                VStack(spacing: 0) {
                    // Top bar: SPOT branding only (no plus; Post is its own tab)
                    TopNavigationView(
                        title: "SPOT",
                        rightButton: .none,
                        showUploadView: .constant(false)
                    )

                    // Feed content only
                    FeedContentView(
                        isLoading: $feedVM.isLoading,
                        spots: feedVM.spots,
                        mapSpots: feedVM.mapSpots,
                        selectedTab: "Feed",
                        onScrolledToBottom: { feedVM.loadMoreSpots() },
                        onRefresh: { await feedVM.refreshFeed() },
                        userId: authVM.userId,
                        onDeleteSpot: { spot in
                            Task { await feedVM.delete(spot: spot) }
                        }
                    )
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if showVerifyToast {
                        ToastView(message: "Please verify your email to post a spot.", isError: true)
                            .transition(.move(edge: .top))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { showVerifyToast = false }
                                }
                            }
                    }
                    if showPostSuccessToast {
                        SuccessToastView(message: "Spot posted!")
                            .transition(.move(edge: .top))
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { showPostSuccessToast = false }
                                }
                            }
                    }
                }
                .padding(.top, 8)
            }
            .background(Color(hex: "F5F3EF"))
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile(let userId):
                    ProfileView(userId: userId, fromNavigationPush: true)
                        .navigationBarBackButtonHidden(true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            Task {
                await feedVM.loadInitialSpots()
            }
            tourManager.configure(userId: authVM.userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotDidPostSuccess)) { _ in
            showPostSuccessToast = true
            Task {
                await feedVM.refreshFeed()
            }
        }
    }
}

// MARK: - Feed Content Component
struct FeedContentView: View {
    @Binding var isLoading: Bool
    let spots: [Spot]
    let mapSpots: [Spot]
    let selectedTab: String
    let onScrolledToBottom: () -> Void
    let onRefresh: () async -> Void
    let userId: String?
    let onDeleteSpot: (Spot) -> Void
    @State private var firstItemRecorded = false
    @State private var failedImageSpotIds: Set<String> = []

    var validSpots: [Spot] { spots }

    var validMapSpots: [Spot] {
        mapSpots.filter { spot in
            spot.latitude != nil &&
            spot.longitude != nil
        }
    }

    var body: some View {
        Group {
            if selectedTab == "Map" {
                MapView(spots: validMapSpots)
                    .ignoresSafeArea(edges: .all)
            } else if isLoading && spots.isEmpty {
                // Skeletons while initial load
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonSpotCard()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if !validSpots.isEmpty {
                ScrollView {
                    RefreshControl(coordinateSpace: .named("RefreshControl")) {
                        failedImageSpotIds.removeAll()
                        Task { await onRefresh() }
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(validSpots.indices, id: \.self) { idx in
                            let spot = validSpots[idx]
                            Group {
                                if (spot.imageURL ?? "").isEmpty {
                                    SkeletonSpotCard()
                                } else {
                                    SpotCard(
                                        spot: spot,
                                        showUserInfo: true,
                                        userId: userId,
                                        onDelete: { onDeleteSpot(spot) },
                                        source: "Feed",
                                        onImageFailure: { failed in
                                            if let failedId = failed.id { failedImageSpotIds.insert(failedId) }
                                        },
                                        onImageRetry: { retrySpot in
                                            // Remove from failed set to allow re-attempt render
                                            if let rid = retrySpot.id { failedImageSpotIds.remove(rid) }
                                        }
                                    )
                                }
                            }
                            .onAppear {
                                if (spot.imageURL ?? "").isEmpty {
                                    SpotLogger.error("Feed missing imageURL for spot id=\(spot.safeId) — rendering placeholder")
                                }
                                if !firstItemRecorded {
                                    let t = PerfMetrics.shared.measure("t_first_item") ?? 0
                                    PerfMetrics.shared.recordOnce("t_first_item", value: t)
                                    firstItemRecorded = true
                                }
                                let progress = Double(idx + 1) / Double(max(validSpots.count, 1))
                                if progress >= 0.7 { onScrolledToBottom() }
                            }
                        }
                        if isLoading {
                            ProgressView().padding()
                        } else {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        if geo.frame(in: .global).maxY < UIScreen.main.bounds.height + 100 {
                                            onScrolledToBottom()
                                        }
                                    }
                            }
                            .frame(height: 1)
                        }
                    }
                }
                .refreshable {
                    failedImageSpotIds.removeAll()
                    await onRefresh()
                }
                .coordinateSpace(name: "RefreshControl")
                .background(Color(hex: "F5F3EF"))
            } else {
                EmptyFeedView()
            }
        }
        .background(Color(hex: "F5F3EF"))
    }
}

struct RefreshControl: View {
    let coordinateSpace: CoordinateSpace
    let onRefresh: () -> Void

    @State private var isRefreshing = false

    var body: some View {
        GeometryReader { geo in
            if geo.frame(in: coordinateSpace).midY > 50 {
                Spacer()
                    .onAppear {
                        if !isRefreshing {
                            isRefreshing = true
                            onRefresh()
                        }
                    }
            } else if geo.frame(in: coordinateSpace).midY < 0 {
                Spacer()
                    .onAppear {
                        isRefreshing = false
                    }
            }
            HStack {
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
                Spacer()
            }
        }
        .padding(.top, -50)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
        }
        .background(Color(hex: "F5F3EF"))
    }
}

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

struct SpotsListView: View {
    let spots: [Spot]

    var body: some View {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(spots) { spot in
                                SpotCard(spot: spot)
                            }
                        }
                        .padding(.vertical, 8)
        }
        .background(Color(hex: "F5F3EF"))
                    }
                }

#Preview() {
    HomepageView()
}

// MARK: - Map Components
struct SpotAnnotation: Identifiable {
    let id = UUID()
    let spot: Spot
    let coordinate: CLLocationCoordinate2D

    init(spot: Spot) {
        self.spot = spot
        self.coordinate = CLLocationCoordinate2D(
            latitude: spot.latitude ?? 0.0,
            longitude: spot.longitude ?? 0.0
        )
    }
}

struct SpotMapMarker: View {
    let spot: Spot
    var body: some View {
        Image("green_marker")
            .resizable()
            .frame(width: 20, height: 20)
    }
}

// SpotCard Preview
#Preview {
    SpotCard(spot: Spot(
        id: "test123",
        userId: "user123",
        username: "TestUser",
        userProfileImageURL: nil,
        imageURL: "https://via.placeholder.com/300",
        vibeTag: "Chill Spot",
        latitude: 37.78,
        longitude: -122.4,
        locationName: "Test Location",
        likes: 5,
        isLiked: false,
        isSaved: false,
        createdAt: Date()
    ))
}
