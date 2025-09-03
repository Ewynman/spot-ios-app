import SwiftUI
import MapKit
import CoreLocation

@MainActor
struct MapView: View {
    let spots: [Spot]
    @StateObject private var locationManager = LocationManager.shared
    @EnvironmentObject var authVM: AuthViewModel

    // iOS 17 camera replacement for coordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var selectedSpot: Spot? = nil

    @Environment(\.verticalSizeClass) private var vSize

    init(spots: [Spot]) {
        self.spots = spots
        _cameraPosition = State(initialValue: .region(LocationManager.shared.getUserRegion()))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Map is isolated in its own view to reduce type-checking load.
                SpotMap(
                    position: $cameraPosition,
                    spots: spots,
                    selectedSpot: selectedSpot,
                    onSelect: select
                )
            }
            // Bottom inset drives the "split" layout; the Map stays alive (prevents Metal crash).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInset(height: openPanelHeight(in: geo.size))
            }
            // Paint content background…
            .background(Constants.Colors.background)
            // …and also paint the TOP safe-area (status/notch) to match your app background.
            .background(Constants.Colors.background.ignoresSafeArea())
            .onAppear {
                locationManager.startUpdatingLocation()
                updateCameraToUser()
            }
            .onDisappear { locationManager.stopUpdatingLocation() }
            .onChange(of: locationManager.userLocation) { _, _ in
                if selectedSpot == nil { updateCameraToUser() }
            }
        }
        // If embedded in a NavigationStack, make the nav bar match the app background.
        .toolbarBackground(Constants.Colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Inset content
    @ViewBuilder
    private func bottomInset(height: CGFloat) -> some View {
        if let spot = selectedSpot {
            FullBleedPanel(spot: spot, onClose: { closePanel() })
                .frame(height: height)
                .transition(.move(edge: .bottom))
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedSpot != nil)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    // Dynamic panel height (no hardcoding)
    private func openPanelHeight(in size: CGSize) -> CGFloat {
        let base: CGFloat = (vSize == .compact) ? size.height * 0.40 : size.height * 0.55
        return min(max(base, 280), size.height * 0.92)
    }

    // MARK: - Actions
    private func select(_ spot: Spot, _ coordinate: CLLocationCoordinate2D) {
        selectedSpot = spot
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }

    private func closePanel() {
        SpotLogger.info("Map.Home.SheetClose")
        selectedSpot = nil
        zoomToFitAllPins()
    }

    private func updateCameraToUser() {
        cameraPosition = .region(locationManager.getUserRegion())
    }

    private func zoomToFitAllPins() {
        let coords: [CLLocationCoordinate2D] = spots.compactMap {
            guard let lat = $0.latitude, let lon = $0.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard let first = coords.first else { updateCameraToUser(); return }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2, longitude: (minLon + maxLon)/2)
        let latDelta = max(0.02, (maxLat - minLat) * 1.3)
        let lonDelta = max(0.02, (maxLon - minLon) * 1.3)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            cameraPosition = .region(.init(center: center, span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta)))
        }
    }
}

// MARK: - Extracted Map (keeps body simple and compiler happy)
private struct SpotMap: View {
    @Binding var position: MapCameraPosition
    let spots: [Spot]
    let selectedSpot: Spot?
    let onSelect: (Spot, CLLocationCoordinate2D) -> Void

    var body: some View {
        Map(position: $position, interactionModes: .all) {
            ForEach(spots, id: \.id) { spot in
                if let coord = coordinate(for: spot) {
                    Annotation("", coordinate: coord) {
                        SpotMapMarker(spot: spot)
                            .scaleEffect(selectedSpot?.id == spot.id ? 1.3 : 1.0)
                            .onTapGesture { onSelect(spot, coord) }
                    }
                }
            }
        }
        // Force LIGHT map look
        .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }

    private func coordinate(for spot: Spot) -> CLLocationCoordinate2D? {
        guard let lat = spot.latitude, let lon = spot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Full-bleed bottom panel (no corners, no shadows)
private struct FullBleedPanel: View {
    let spot: Spot
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // X at TOP-LEFT
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Constants.Colors.primary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)

            SpotCard(
                spot: spot,
                showUserInfo: true,
                userId: nil,
                onDelete: { },
                source: "Map"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        // Full-bleed, no rounded corners/shadows; covers home indicator.
        .background(Constants.Colors.background)
        .ignoresSafeArea(edges: .bottom)
    }
}
