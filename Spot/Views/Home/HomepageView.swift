import SwiftUI
import MapKit
import FirebaseFirestore // Added for DocumentSnapshot

class FeedViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var mapSpots: [Spot] = []
    @Published var isLoading = false
    @Published var hasMore = true
    private var loadTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
    }
    
    func loadInitialSpots() async {
        // Cancel any existing task
        loadTask?.cancel()
        
        // Start new loading task
        loadTask = Task {
            do {
                await MainActor.run {
                    isLoading = true
                }
                let spots = try await FeedCache.shared.loadInitialSpots()
                
                await MainActor.run {
                    self.spots = spots
                    self.mapSpots = spots
                    self.hasMore = spots.count == 10 // pageSize
                    self.isLoading = false
                }
            } catch {
                SpotLogger.error("Failed to load initial spots: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.spots = []
                    self.mapSpots = []
                    self.hasMore = false
                }
            }
        }
    }
    
    func loadMoreSpots() {
        guard !isLoading, hasMore else { return }
        
        // Cancel any existing task
        loadTask?.cancel()
        
        // Start new loading task
        loadTask = Task {
            do {
                await MainActor.run {
                    isLoading = true
                }
                let newSpots = try await FeedCache.shared.loadMoreSpots()
                
                await MainActor.run {
                    self.spots.append(contentsOf: newSpots)
                    self.mapSpots.append(contentsOf: newSpots)
                    self.hasMore = newSpots.count == 10 // pageSize
                    self.isLoading = false
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
                    self.hasMore = spots.count == 10 // pageSize
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
    @State private var feedViewType = "Feed" // "Feed" or "Map"
    private let feedTabs = ["Feed", "Map"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Show different content based on selected tab
                Group {
                    if selectedTab == "Profile" {
                        ProfileView() // nil means current user's profile
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
                                    onRefresh: { feedVM.refreshFeed() }
                                )
                                .transition(.opacity)
                            } else {
                                // Search View (to be implemented)
                                Text("Search")
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
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
            // Load data in background without blocking UI
            Task {
                await feedVM.loadInitialSpots()
            }
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
                MapView(spots: validSpots)
                    .edgesIgnoringSafeArea(.all)
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
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { selectedTab = "Search" }) {
                BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: selectedTab == "Search")
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { selectedTab = "Profile" }) {
                BottomNavItem(icon: "person", title: "Profile", isSelected: selectedTab == "Profile")
            }
            .buttonStyle(PlainButtonStyle())
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
