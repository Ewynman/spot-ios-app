import SwiftUI
import MapKit

struct ProfileMapView: View {
    let spots: [Spot]
    @State private var region: MKCoordinateRegion
    @State private var selectedSpot: Spot?
    @State private var showSpotDetail = false
    
    init(spots: [Spot]) {
        self.spots = spots
        // Initialize with Miami Beach, will be updated in onAppear
        self._region = State(initialValue: LocationManager.shared.getRegionForSpots(spots))
    }
    
    var body: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                Map(
                    coordinateRegion: $region,
                    annotationItems: spots.map { SpotAnnotation(spot: $0) }
                ) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        SpotMapMarker(spot: annotation.spot)
                            .onTapGesture {
                                selectedSpot = annotation.spot
                                withAnimation {
                                    region = MKCoordinateRegion(
                                        center: annotation.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                }
                                showSpotDetail = true
                            }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .onAppear {
                    updateRegion()
                }
                .onChange(of: spots.count) { _ in
                    updateRegion()
                }
            } else {
                Map(
                    coordinateRegion: $region,
                    annotationItems: spots.map { SpotAnnotation(spot: $0) }
                ) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        SpotMapMarker(spot: annotation.spot)
                            .onTapGesture {
                                selectedSpot = annotation.spot
                                withAnimation {
                                    region = MKCoordinateRegion(
                                        center: annotation.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                }
                                showSpotDetail = true
                            }
                    }
                }
                .onAppear {
                    updateRegion()
                }
                .onChange(of: spots.count) { _ in
                    updateRegion()
                }
            }
        }
        .sheet(isPresented: $showSpotDetail) {
            if let spot = selectedSpot {
                SpotDetailModalView(spot: spot)
            }
        }
    }
    
    private func updateRegion() {
        withAnimation {
            region = LocationManager.shared.getRegionForSpots(spots)
        }
    }
}

// MARK: - Spot Detail Modal View
struct SpotDetailModalView: View {
    let spot: Spot
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    
    init(spot: Spot) {
        self.spot = spot
        
        // Initialize map region
        if let lat = spot.latitude, let long = spot.longitude {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: long),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        
        _isLiked = State(initialValue: spot.isLiked ?? false)
        _isSaved = State(initialValue: spot.isSaved ?? false)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back to map")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // User Info
            HStack {
                if let profileImageURL = spot.userProfileImageURL {
                    AsyncImage(url: URL(string: profileImageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 32, height: 32)
                    }
                }
                
                Text(spot.username ?? "")
                    .font(FontManager.primaryText())
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let locationName = spot.locationName {
                    Text(locationName)
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Map at the top
            Map(coordinateRegion: $region,
                annotationItems: [spot]) { spot in
                MapAnnotation(coordinate: CLLocationCoordinate2D(
                    latitude: spot.latitude ?? 0,
                    longitude: spot.longitude ?? 0
                )) {
                    Image("green_marker")
                        .resizable()
                        .frame(width: 40, height: 40)
                }
            }
            .frame(height: 200)
            
            // Spot Image
            if let imageURL = spot.imageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: 300)
                }
            }
            
            // Interaction Bar
            HStack {
                HStack(spacing: 16) {
                    Button(action: { isLiked.toggle() }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? .red : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { isSaved.toggle() }) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isSaved ? Constants.Colors.primary : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                if let vibe = spot.vibeTag {
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
            .padding(.vertical, 12)
        }
        .background(Color(hex: "F5F3EF"))
    }
} 