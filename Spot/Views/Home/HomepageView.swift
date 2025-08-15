import SwiftUI
import MapKit
import FirebaseFirestore // Added for DocumentSnapshot

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
                self.hasMore = true
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
            let beforeCount = repo.spots.count
            await repo.loadMore()
            await MainActor.run {
                let new = repo.spots
                let appended = max(0, new.count - beforeCount)
                self.spots = new
                // hasMore: optimistic true if we appended at least ~page size/2; will disable when cursors exhaust
                self.hasMore = appended > 0
                self.isLoading = false
            }
        }
    }
    
    func refreshFeed() {
        // Cancel any existing task
        loadTask?.cancel()
        
        // Start new refresh task
        loadTask = Task {
            do {
                await MainActor.run {
                    isLoading = true
                }
                let spots = try await FeedCache.shared.refreshFeed()
                
                await MainActor.run {
                    self.spots = spots
                    self.mapSpots = spots
                    self.hasMore = spots.count >= 24
                    self.isLoading = false
                }
            } catch {
                SpotLogger.error("Failed to refresh feed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadMapSpots(forceRefresh: Bool = false) {
        SpotLogger.debug("Loading spots for map")
        SpotService.shared.fetchSpotsForMap(forceRefresh: forceRefresh) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let spots):
                    SpotLogger.info("Loaded \(spots.count) spots for map")
                    self.mapSpots = spots
                case .failure(let error):
                    SpotLogger.error("Failed to load map spots: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Delete
    @MainActor
    func delete(spot: Spot) async {
        guard let id = spot.id else {
            SpotLogger.error("Delete requested for spot without id")
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
            SpotLogger.info("Deleting spot id=\(id)")
            // Run deletion off main
            try await SpotService.shared.deleteSpot(spot)
            deletingSpotIds.remove(id)
            // Force refresh map spots after successful deletion
            loadMapSpots(forceRefresh: true)
        } catch {
            SpotLogger.error("Delete failed for id=\(id): \(error.localizedDescription)")
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
    @State private var selectedTab = "Home"
    @State private var showUploadView = false
    @State private var feedViewType = "Feed" // "Feed" or "Map"
    private let feedTabs = ["Feed", "Map"]
    // Tour
    @StateObject private var tourManager = HomeTourManager()
    var isFirstSessionAfterSignup: Bool { authVM.isAuthenticated && (authVM.likedSpots.isEmpty && authVM.bookmarkedSpots.isEmpty) && !tourManager.hasSeenHomeTour }
    @State private var coachFrames: [CoachTarget: CGRect] = [:]
    
    var body: some View {
        NavigationStack {
            HomeTourHost(manager: tourManager, coachFrames: $coachFrames, isFirstSessionAfterSignup: isFirstSessionAfterSignup) {
                VStack(spacing: 0) {
                // Show different content based on selected tab
                Group {
                    if selectedTab == "Profile" {
                        ProfileView(userId: authVM.userId)
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 0) {
                            // Top Navigation with SPOT branding
                            TopNavigationView(
                                title: "SPOT",
                                rightButton: .plus,
                                showUploadView: $showUploadView
                            )
                            
                            if selectedTab == "Home" {
                                // Feed/Map Toggle
                                VStack(spacing: 0) {
                                    HStack(spacing: 32) {
                                        ForEach(feedTabs, id: \.self) { tab in
                                            VStack(spacing: 4) {
                                                Text(tab)
                                                    .font(FontManager.primaryText())
                                                    .fontWeight(feedViewType == tab ? .semibold : .regular)
                                                    .foregroundColor(feedViewType == tab ? Constants.Colors.primary : .gray)
                                                
                                                Rectangle()
                                                    .fill(feedViewType == tab ? Constants.Colors.primary : Color.clear)
                                                    .frame(height: 2)
                                            }
                                            .onTapGesture {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    feedViewType = tab
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .padding(.top, 24)
                                
                                // Feed Content
                                FeedContentView(
                                    isLoading: $feedVM.isLoading,
                                    spots: feedVM.spots,
                                    mapSpots: feedVM.mapSpots,
                                    selectedTab: feedViewType,
                                    onScrolledToBottom: { feedVM.loadMoreSpots() },
                                    onRefresh: { feedVM.refreshFeed() },
                                 userId: authVM.userId,
                                 onDeleteSpot: { spot in
                                     Task { await feedVM.delete(spot: spot) }
                                 }
                                )
                                .transition(.opacity)
                             .onChange(of: feedViewType) { newValue in
                                 if newValue == "Map" {
                                     feedVM.loadMapSpots(forceRefresh: true)
                                 }
                             }
                            } else {
                                // Search View
                                SearchView()
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                // Bottom Navigation
                BottomNavigationView(selectedTab: $selectedTab)
                    .padding(.bottom, 0)
                    .background(Color(hex: "F5F3EF"))
            }
            }
            .background(Color(hex: "F5F3EF"))
//            .overlay(alignment: .topLeading) { DebugPerfOverlay() }
            .navigationDestination(isPresented: $showUploadView) {
                PostFlowView(onPostSuccess: {
                    feedVM.refreshFeed()
                })
            }
        }
        .onAppear {
            // Load data in background without blocking UI
            Task {
                await feedVM.loadInitialSpots()
            }
            // Configure per-user tour persistence key
            tourManager.configure(userId: authVM.userId)
            // Warm map data for first visit
            feedVM.loadMapSpots()
        }
    }
}

// MARK: - Tab Navigation Component
struct TabNavigationView: View {
    @Binding var selectedTab: String
    let tabs: [String]
    
    var body: some View {
                    HStack(spacing: 32) {
                        ForEach(tabs, id: \.self) { tab in
                TabItemView(tab: tab, isSelected: selectedTab == tab) {
                    SpotLogger.debug("User switched to tab: \(tab)")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            }
                        }
                    }
        .padding(.horizontal, 16)
        .background(Color(hex: "F5F3EF"))
    }
}

struct TabItemView: View {
    let tab: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            Text(tab)
                .font(FontManager.primaryText())
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Constants.Colors.primary : .gray)
            
            Rectangle()
                .fill(isSelected ? Constants.Colors.primary : Color.clear)
                .frame(height: 2)
        }
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Feed Content Component
struct FeedContentView: View {
    @Binding var isLoading: Bool
    let spots: [Spot]
    let mapSpots: [Spot]
    let selectedTab: String
    let onScrolledToBottom: () -> Void
    let onRefresh: () -> Void
    let userId: String?
    let onDeleteSpot: (Spot) -> Void
    @State private var firstItemRecorded = false
    
    var validSpots: [Spot] {
        spots.filter { spot in
            // Relax createdAt to allow immediate visibility after posting (serverTimestamp may be pending)
            !(spot.imageURL ?? "").isEmpty &&
            !(spot.username ?? "").isEmpty &&
            spot.latitude != nil &&
            spot.longitude != nil
        }
    }
    
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
                    .edgesIgnoringSafeArea(.all)
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
                        onRefresh()
                    }
                    
                    LazyVStack(spacing: 0) {
                        ForEach(Array(validSpots.enumerated()), id: \.offset) { idx, spot in
                            SpotCard(spot: spot, showUserInfo: true, userId: userId, onDelete: { onDeleteSpot(spot) }, source: "Feed")
                                .onAppear {
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
