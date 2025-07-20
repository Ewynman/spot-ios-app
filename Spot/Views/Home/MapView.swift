import SwiftUI
import MapKit

struct MapView: View {
    let spots: [Spot]
    @StateObject private var locationManager = LocationManager.shared
    @State private var region: MKCoordinateRegion
    
    init(spots: [Spot]) {
        self.spots = spots
        // Initialize with user location or Miami Beach, will be updated in onAppear
        self._region = State(initialValue: LocationManager.shared.getUserRegion())
    }
    
    var body: some View {
        if #available(iOS 17.0, *) {
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onAppear {
                locationManager.startUpdatingLocation()
                updateRegion()
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .onChange(of: locationManager.userLocation) { _ in
                updateRegion()
            }
        } else {
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: spots.map { SpotAnnotation(spot: $0) }
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    SpotMapMarker(spot: annotation.spot)
                }
            }
            .onAppear {
                locationManager.startUpdatingLocation()
                updateRegion()
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .onChange(of: locationManager.userLocation) { _ in
                updateRegion()
            }
        }
    }
    
    private func updateRegion() {
        withAnimation {
            region = locationManager.getUserRegion()
        }
    }
} 