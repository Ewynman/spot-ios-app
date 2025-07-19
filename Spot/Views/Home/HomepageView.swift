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
    
    func loadInitialSpots() {
        SpotLogger.debug("FeedViewModel: Running feed query with order by 'createdAt'")
        isLoading = true
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        query.getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    SpotLogger.error("FeedViewModel: Failed to load spots: \(error.localizedDescription)")
                    self.spots = []
                    self.hasMore = false
                    return
                }
                guard let snapshot = snapshot else {
                    SpotLogger.warning("FeedViewModel: No documents returned for feed")
                    self.spots = []
                    self.hasMore = false
                    return
                }
                self.spots = snapshot.documents.compactMap { doc in
                    do {
                        let spot = try doc.data(as: Spot.self)
                        return spot
                    } catch {
                        SpotLogger.error("FeedViewModel: Failed to decode spot doc id: \(doc.documentID) - \(error)")
                        return nil
                    }
                }
                SpotLogger.info("FeedViewModel: Parsed \(self.spots.count) spots for feed")
                self.lastDocument = snapshot.documents.last
                self.hasMore = snapshot.documents.count == self.pageSize
            }
        }
    }
    
    func loadMoreSpots() {
        guard !isLoading, hasMore, let lastDoc = lastDocument else { return }
        SpotLogger.debug("FeedViewModel: Loading more spots for feed")
        isLoading = true
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
        query.getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    SpotLogger.error("FeedViewModel: Failed to load more spots: \(error.localizedDescription)")
                    self.hasMore = false
                    return
                }
                guard let snapshot = snapshot else {
                    SpotLogger.warning("FeedViewModel: No more documents returned for feed")
                    self.hasMore = false
                    return
                }
                let newSpots = snapshot.documents.compactMap { doc in
                    SpotLogger.debug("FeedViewModel: Parsing spot doc id: \(doc.documentID)")
                    return try? doc.data(as: Spot.self)
                }
                SpotLogger.info("FeedViewModel: Parsed \(newSpots.count) new spots for feed")
                self.spots.append(contentsOf: newSpots)
                self.lastDocument = snapshot.documents.last
                self.hasMore = snapshot.documents.count == self.pageSize
            }
        }
    }
    
    func refreshFeed() {
        lastDocument = nil
        hasMore = true
        loadInitialSpots()
        loadMapSpots()
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
    @State private var selectedTab = "Feed"
    @State private var showUploadView = false
    private let tabs = ["Feed", "Map"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Navigation with SPOT branding
                TopNavigationView(showUploadView: $showUploadView)
                // Tab Navigation
                TabNavigationView(selectedTab: $selectedTab, tabs: tabs)
                // Feed Content
                FeedContentView(
                    isLoading: $feedVM.isLoading,
                    spots: feedVM.spots,
                    mapSpots: feedVM.mapSpots,
                    selectedTab: selectedTab,
                    onScrolledToBottom: { feedVM.loadMoreSpots() }
                )
                // Bottom Navigation
                BottomNavigationView()
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

// MARK: - Top Navigation Component
struct TopNavigationView: View {
    @Binding var showUploadView: Bool
    
    var body: some View {
                VStack(spacing: 16) {
                    HStack {
                Text("SPOT")
                    .font(FontManager.logoTitle())
                    .foregroundColor(Constants.Colors.primary)
                        Spacer()
                        Button(action: {
                    print("➕ Plus button tapped!")
                    SpotLogger.info("User tapped + button to start post flow")
                            showUploadView = true
                    print("showUploadView set to: \(showUploadView)")
                        }) {
                            Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Constants.Colors.primary)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .background(Color(hex: "F5F3EF"))
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
            } else if isLoading {
                LoadingView()
            } else if !validSpots.isEmpty {
                ScrollView {
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
                .background(Color(hex: "F5F3EF"))
            } else {
                EmptyFeedView()
            }
        }
        .background(Color(hex: "F5F3EF"))
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
    var body: some View {
                HStack(spacing: 0) {
            BottomNavItem(icon: "house.fill", title: "Home", isSelected: true)
            BottomNavItem(icon: "magnifyingglass", title: "Search", isSelected: false)
            BottomNavItem(icon: "person", title: "Profile", isSelected: false)
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
