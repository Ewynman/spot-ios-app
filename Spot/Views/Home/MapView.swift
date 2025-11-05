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
    @State private var selectedSpot: Spot?
    @State private var hasPerformedInitialFit: Bool = false

    @Environment(\.verticalSizeClass) private var vSize

    init(spots: [Spot]) {
        self.spots = spots
        _cameraPosition = State(initialValue: .region(LocationManager.shared.getUserRegion()))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Clustered map (UIKit-backed) for performance with many pins
                ClusteredSpotMap(spots: spots) { spot, coord in
                    select(spot, coord)
                }
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
                performInitialFitIfNeeded()
            }
            .onDisappear { locationManager.stopUpdatingLocation() }
            .onChange(of: locationManager.userLocation) { _, _ in
                // Only follow user if there are no map spots; otherwise preserve the fit-to-pins.
                if selectedSpot == nil && !hasValidSpots { updateCameraToUser() }
            }
            .onChange(of: spots) { _, _ in
                // When spots load asynchronously, perform initial fit once.
                performInitialFitIfNeeded()
            }
        }
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
        // Centering handled by ClusteredSpotMap coordinator
    }

    private func closePanel() {
        SpotLogger.info("Map.Home.SheetClose")
        selectedSpot = nil
        zoomToFitAllPins()
    }

    private func updateCameraToUser() {
        cameraPosition = .region(locationManager.getUserRegion())
    }

    private func zoomToFitAllPins() { /* handled inside ClusteredSpotMap */ }

    private var hasValidSpots: Bool {
        return spots.contains { $0.latitude != nil && $0.longitude != nil }
    }

    private func performInitialFitIfNeeded() {
        guard !hasPerformedInitialFit else { return }
        if hasValidSpots {
            // Clustered map handles initial fit on first update
        } else {
            updateCameraToUser()
        }
        hasPerformedInitialFit = true
    }
}

#Preview {
    let spots = [
        Spot(id: "1", userId: "u1", username: "eddie", imageURL: "https://picsum.photos/seed/3/800/600", vibeTag: "Park", latitude: 40.7128, longitude: -74.0060, locationName: "NYC", createdAt: Date())
    ]
    let auth = AuthViewModel()
    return MapView(spots: spots).environmentObject(auth)
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

// MARK: - UIKit-backed clustered map
private struct ClusteredSpotMap: UIViewRepresentable {
    let spots: [Spot]
    let onSelect: (Spot, CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        // Always light mode
        if #available(iOS 13.0, *) { map.overrideUserInterfaceStyle = .light }
        // Standard light configuration
        if #available(iOS 13.0, *) {
            let cfg = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            map.preferredConfiguration = cfg
        }
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "SpotImage")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let existing = map.annotations.compactMap { $0 as? SpotPointAnnotation }
        if existing.count != spots.count {
            map.removeAnnotations(existing)
            let anns: [SpotPointAnnotation] = spots.compactMap { s in
                guard let lat = s.latitude, let lon = s.longitude else { return nil }
                let a = SpotPointAnnotation(spot: s)
                a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                a.title = s.vibeTag
                return a
            }
            map.addAnnotations(anns)
            if !anns.isEmpty {
                map.showAnnotations(anns, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusteredSpotMap
        init(_ parent: ClusteredSpotMap) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(Constants.Colors.primary)
                return view
            }
            guard let ann = annotation as? SpotPointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "SpotImage", for: ann)
            view.clusteringIdentifier = "spot"
            view.canShowCallout = false
            // Custom image marker
            if let img = UIImage(named: "green_marker") {
                view.image = img
                view.centerOffset = CGPoint(x: 0, y: -img.size.height * 0.4)
            } else {
                // Fallback to a tinted marker if asset missing
                let marker = MKMarkerAnnotationView(annotation: ann, reuseIdentifier: nil)
                marker.clusteringIdentifier = "spot"
                marker.markerTintColor = UIColor(Constants.Colors.primary)
                return marker
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            guard let ann = view.annotation as? SpotPointAnnotation else { return }
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            mapView.setRegion(MKCoordinateRegion(center: ann.coordinate, span: span), animated: true)
            parent.onSelect(ann.spot, ann.coordinate)
        }
    }
}

private final class SpotPointAnnotation: MKPointAnnotation {
    let spot: Spot
    init(spot: Spot) { self.spot = spot; super.init() }
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
