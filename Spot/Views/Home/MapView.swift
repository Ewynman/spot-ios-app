import SwiftUI
import MapKit

struct MapView: View {
    let spots: [Spot]
    @StateObject private var locationManager = LocationManager.shared
    @State private var region: MKCoordinateRegion
    @State private var selectedSpot: Spot?
    @State private var showSpotDetail = false
    
    init(spots: [Spot]) {
        self.spots = spots
        self._region = State(initialValue: LocationManager.shared.getUserRegion())
    }
    
    var body: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                Map(
                    coordinateRegion: $region,
                    showsUserLocation: true,
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
        .sheet(isPresented: $showSpotDetail) {
            if let spot = selectedSpot {
                SpotDetailModalView(spot: spot)
            }
        }
    }
    
    private func updateRegion() {
        withAnimation {
            region = locationManager.getUserRegion()
        }
    }
} 