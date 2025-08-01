import SwiftUI
import MapKit

struct SpotDetailView: View {
    let spot: Spot
    let isMapView: Bool // true if opened from map, false if opened from grid
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion
    @State private var isLiked: Bool
    @State private var isSaved: Bool
    
    init(spot: Spot, isMapView: Bool) {
        self.spot = spot
        self.isMapView = isMapView
        
        // Initialize map region if we have coordinates
        if let lat = spot.latitude, let long = spot.longitude {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: long),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            // Default to Miami if no coordinates (shouldn't happen)
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
                // Back Button
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(isMapView ? "Back to map" : "Back to all spots")
                            .font(FontManager.primaryText())
                    }
                    .foregroundColor(Constants.Colors.primary)
                }
                
                Spacer()
                
                if isMapView {
                    // Close Button for map view
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if isMapView {
                // User Info for map view
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
            }
            
            ScrollView {
                VStack(spacing: 0) {
                    // Spot Image
                    if let imageURL = spot.imageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(4/3, contentMode: .fit)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(4/3, contentMode: .fit)
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
                    
                    if !isMapView {
                        // Location info for grid view
                        if let locationName = spot.locationName {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(Constants.Colors.primary)
                                Text(locationName)
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
            
            if isMapView {
                // Map for map view
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
            }
        }
        .background(Color(hex: "F5F3EF"))
    }
} 