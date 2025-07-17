import SwiftUI
import MapKit

struct HomepageView: View {
    @State private var selectedTab = "Feed"
    @State private var spots: [Spot] = []
    @State private var mapSpots: [Spot] = []
    @State private var isLoading = true
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
                FeedContentView(isLoading: $isLoading, spots: spots, mapSpots: mapSpots, selectedTab: selectedTab)
                
                // Bottom Navigation
                BottomNavigationView()
            }
            .background(Color(hex: "F5F3EF"))
        }
        .navigationDestination(isPresented: $showUploadView) {
            SpotUploadView()
        }
        .onAppear {
            loadSpots()
            loadMapSpots()
        }
    }
    
    private func loadSpots() {
        // TODO: Load spots from Firebase
        // For now, just show empty state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isLoading = false
        }
    }
    
    private func loadMapSpots() {
        SpotService.shared.fetchSpotsForMap { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let spots):
                    self.mapSpots = spots
                case .failure(let error):
                    print("Failed to load map spots: \(error.localizedDescription)")
                }
            }
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
                    showUploadView = true
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
    
    var body: some View {
        Group {
            if selectedTab == "Map" {
                MapView(spots: mapSpots)
            } else if isLoading {
                LoadingView()
            } else if spots.isEmpty {
                EmptyFeedView()
            } else {
                SpotsListView(spots: spots)
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
        Map(coordinateRegion: $region, annotationItems: spots.map { SpotAnnotation(spot: $0) }) { annotation in
            MapAnnotation(coordinate: annotation.coordinate) {
                SpotMapMarker(spot: annotation.spot)
            }
        }
        .onAppear {
            loadSpotsForMap()
        }
    }
    
    private func loadSpotsForMap() {
        // TODO: Load spots from Firebase and update region
        // For now, we'll use the spots passed in
    }
}

struct SpotMapMarker: View {
    let spot: Spot
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Constants.Colors.primary)
            
            Text((((spot.caption?.isEmpty) != nil) ? "Spot" : spot.caption) ?? "")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 2)
        }
    }
}
