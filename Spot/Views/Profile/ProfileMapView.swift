import SwiftUI
import MapKit

struct ProfileMapView: View {
    let spots: [Spot]
    @State private var region: MKCoordinateRegion
    
    init(spots: [Spot]) {
        self.spots = spots
        // Initialize with Miami Beach, will be updated in onAppear
        self._region = State(initialValue: LocationManager.shared.getRegionForSpots(spots))
    }
    
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
    
    private func updateRegion() {
        withAnimation {
            region = LocationManager.shared.getRegionForSpots(spots)
        }
    }
} 