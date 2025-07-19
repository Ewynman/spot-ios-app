import SwiftUI
import MapKit
import FirebaseFirestore // Added for DocumentSnapshot

class FeedViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var mapSpots: [Spot] = []
    @Published var isLoading = false
    @Published var hasMore = true
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 10
    private var loadTask: Task<Void, Never>?
    
    // Cache management
    private var cachedSpots: [Spot] = []
    private var lastCacheTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private var isCacheValid: Bool {
        guard let lastTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(lastTime) < cacheValidityDuration
    }
    
    func loadInitialSpots() {
        // Cancel any existing load task
        loadTask?.cancel()
        
        // If cache is valid, use it immediately
        if !cachedSpots.isEmpty && isCacheValid {
            spots = cachedSpots
            mapSpots = cachedSpots
            SpotLogger.info("Using cached spots: \(cachedSpots.count) spots")
            // Still refresh in background for updates
            refreshInBackground()
            return
        }
        
        SpotLogger.debug("FeedViewModel: Running initial feed query")
        isLoading = true
        
        loadTask = Task {
            do {
                let query = Firestore.firestore().collection("spots")
                    .order(by: "createdAt", descending: true)
                    .limit(to: pageSize)
                
                let snapshot = try await query.getDocuments()
                
                let newSpots = snapshot.documents.compactMap { doc -> Spot? in
                    do {
                        return try doc.data(as: Spot.self)
                    } catch {
                        SpotLogger.error("Failed to decode spot: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                await MainActor.run {
                    self.spots = newSpots
                    self.mapSpots = newSpots
                    self.lastDocument = snapshot.documents.last
                    self.hasMore = snapshot.documents.count == self.pageSize
                    self.isLoading = false
                    
                    // Update cache
                    self.cachedSpots = newSpots
                    self.lastCacheTime = Date()
                    
                    SpotLogger.info("Loaded and cached \(newSpots.count) spots")
                }
            } catch {
                SpotLogger.error("Failed to load spots: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.spots = []
                    self.mapSpots = []
                    self.hasMore = false
                }
            }
        }
    }
    
    private func refreshInBackground() {
        Task {
            do {
                let query = Firestore.firestore().collection("spots")
                    .order(by: "createdAt", descending: true)
                    .limit(to: pageSize)
                
                let snapshot = try await query.getDocuments()
                let newSpots = snapshot.documents.compactMap { doc -> Spot? in
                    try? doc.data(as: Spot.self)
                }
                
                // Only update if there are changes
                if !newSpots.isEmpty && newSpots != spots {
                    await MainActor.run {
                        self.spots = newSpots
                        self.mapSpots = newSpots
                        self.cachedSpots = newSpots
                        self.lastCacheTime = Date()
                        self.lastDocument = snapshot.documents.last
                        self.hasMore = snapshot.documents.count == self.pageSize
                        SpotLogger.info("Updated feed with \(newSpots.count) spots")
                    }
                }
            } catch {
                SpotLogger.error("Background refresh failed: \(error.localizedDescription)")
            }
        }
    }
    
    func loadMoreSpots() {
        guard !isLoading, hasMore, let lastDoc = lastDocument else { return }
        
        isLoading = true
        loadTask = Task {
            do {
                let query = Firestore.firestore().collection("spots")
                    .order(by: "createdAt", descending: true)
                    .start(afterDocument: lastDoc)
                    .limit(to: pageSize)
                
                let snapshot = try await query.getDocuments()
                let newSpots = snapshot.documents.compactMap { doc -> Spot? in
                    try? doc.data(as: Spot.self)
                }
                
                await MainActor.run {
                    self.spots.append(contentsOf: newSpots)
                    self.mapSpots.append(contentsOf: newSpots)
                    self.lastDocument = snapshot.documents.last
                    self.hasMore = snapshot.documents.count == self.pageSize
                    self.isLoading = false
                    SpotLogger.info("Loaded \(newSpots.count) more spots")
                }
            } catch {
                SpotLogger.error("Failed to load more spots: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.hasMore = false
                }
            }
        }
    }
    
    func refreshFeed() {
        lastDocument = nil
        hasMore = true
        loadInitialSpots()
    }
    
    deinit {
        loadTask?.cancel()
    }
    
    func loadMapSpots() {
        SpotLogger.debug("Loading spots for map")
        SpotService.shared.fetchSpotsForMap { result in
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
}

struct HomepageView: View {
    @StateObject private var feedVM = FeedViewModel()
    @State private var selectedTab = "Home"
    @State private var showUploadView = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Show different content based on selected tab
                if selectedTab == "Profile" {
                    ProfileView()
                } else {
                    // Top Navigation with SPOT branding
                    TopNavigationView(
                        title: "SPOT",
                        rightButton: .plus,
                        showUploadView: $showUploadView
                    )
                    
                    if selectedTab == "Home" {
                        // Feed Content
                        FeedContentView(
                            isLoading: $feedVM.isLoading,
                            spots: feedVM.spots,
                            mapSpots: feedVM.mapSpots,
                            selectedTab: selectedTab,
                            onScrolledToBottom: { feedVM.loadMoreSpots() },
                            onRefresh: { feedVM.refreshFeed() }
                        )
                    } else {
                        // Search View (to be implemented)
                        Text("Search")
                    }
                }
                
                // Bottom Navigation
                BottomNavigationView(selectedTab: $selectedTab)
            }
            .background(Color(hex: "F5F3EF"))
            .navigationDestination(isPresented: $showUploadView) {
                PostFlowView(onPostSuccess: {
                    feedVM.refreshFeed()
                })
            }
        }
        .onAppear {
            feedVM.loadInitialSpots()
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
    
    var validSpots: [Spot] {
        spots.filter { spot in
            !(spot.imageURL ?? "").isEmpty &&
            !(spot.username ?? "").isEmpty &&
            !(spot.vibeTag ?? "").isEmpty &&
            spot.latitude != nil &&
            spot.longitude != nil &&
            spot.createdAt != nil
        }
    }
    
    var body: some View {
        Group {
            if selectedTab == "Map" {
                MapView(spots: mapSpots)
            } else if isLoading && spots.isEmpty {
                LoadingView()
            } else if !validSpots.isEmpty {
                ScrollView {
                    RefreshControl(coordinateSpace: .named("RefreshControl")) {
                        onRefresh()
                    }
                    
                    LazyVStack(spacing: 0) {
                        ForEach(validSpots) { spot in
                            SpotCard(spot: spot)
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
                    .padding(.vertical, 8)
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
                
// MARK: - Bottom Navigation Component
struct BottomNavigationView: View {
    @Binding var selectedTab: String
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: { selectedTab = "Home" }) {
                BottomNavItem(icon: "house.fill", title: "Home", isSelected: selectedTab == "Home")
            }
            
            Button(action: { selectedTab = "Search" }) {
                BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: selectedTab == "Search")
            }
            
            Button(action: { selectedTab = "Profile" }) {
                BottomNavItem(icon: "person", title: "Profile", isSelected: selectedTab == "Profile")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Constants.Colors.background)
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct BottomNavItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? Constants.Colors.primary : .gray)
            
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(isSelected ? Constants.Colors.primary : .gray)
        }
        .frame(maxWidth: .infinity)
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

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.060), // Default to NYC
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    let spots: [Spot]
    
    var body: some View {
        if #available(iOS 17.0, *) {
            Map(
                coordinateRegion: $region,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onAppear {
                recenterMap()
            }
            .onChange(of: spots.count) { _ in
                recenterMap()
            }
        } else {
            Map(
                coordinateRegion: $region,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
            .onAppear {
                recenterMap()
            }
            .onChange(of: spots.count) { _ in
                recenterMap()
            }
        }
    }
    
    private func recenterMap() {
        guard !spots.isEmpty else { return }
        if spots.count == 1, let lat = spots.first?.latitude, let lng = spots.first?.longitude {
            region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            region.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        } else {
            let lats = spots.compactMap { $0.latitude }
            let lngs = spots.compactMap { $0.longitude }
            guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return }
            let centerLat = (minLat + maxLat) / 2
            let centerLng = (minLng + maxLng) / 2
            let spanLat = max(0.01, (maxLat - minLat) * 1.5)
            let spanLng = max(0.01, (maxLng - minLng) * 1.5)
            region.center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
            region.span = MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLng)
        }
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
        caption: "A cool spot!",
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
