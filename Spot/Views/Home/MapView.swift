import SwiftUI
import MapKit
import CoreLocation

@MainActor
struct MapView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @EnvironmentObject var authVM: AuthViewModel

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedSpot: Spot?
    @State private var hasPerformedInitialFit: Bool = false
    @State private var regionLoadTask: Task<Void, Never>?

    @Environment(\.verticalSizeClass) private var vSize

    init(spots: [Spot] = []) {
        _cameraPosition = State(initialValue: .region(LocationManager.shared.getUserRegion()))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ClusteredSpotMap(spots: mapVM.visibleSpots, onRegionChanged: { _ in
                    // Region changes don't need to reload - we show all spots
                }) { spot, coord in
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
                mapVM.loadAllSpots()
            }
            .onDisappear { 
                locationManager.stopUpdatingLocation()
                // Clear selected spot to ensure map resources are released before navigation
                selectedSpot = nil
                mapVM.clearVisibleSpots()
                // Cancel any pending region load tasks
                regionLoadTask?.cancel()
                regionLoadTask = nil
            }
            .onChange(of: locationManager.userLocation) { oldLocation, newLocation in
                // Zoom to user location when it first becomes available
                if oldLocation == nil && newLocation != nil && selectedSpot == nil && !hasPerformedInitialFit {
                    updateCameraToUser()
                    hasPerformedInitialFit = true
                }
            }
            .onChange(of: mapVM.visibleSpots) { _, _ in
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
        SpotLogger.log(MapViewLogs.homeSheetClose)
        selectedSpot = nil
        // no-op; cluster map maintains region
    }

    private func updateCameraToUser() {
        cameraPosition = .region(locationManager.getUserRegion())
    }

    private func zoomToFitAllPins() { /* handled inside ClusteredSpotMap */ }

    private var hasValidSpots: Bool {
        return mapVM.visibleSpots.contains { $0.latitude != nil && $0.longitude != nil }
    }

    private func performInitialFitIfNeeded() {
        guard !hasPerformedInitialFit else { return }
        if hasValidSpots {
            // Wait for first regionChanged to request viewport data
        } else {
            updateCameraToUser()
        }
        hasPerformedInitialFit = true
    }

    private func debounceLoad(for _: MKCoordinateRegion) {
        // Keep for region changes if needed, but initial load uses loadAllSpots
        regionLoadTask?.cancel()
        regionLoadTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            if Task.isCancelled { return }
            // Optionally reload visible region spots, but we're showing all spots now
        }
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
    var onRegionChanged: ((MKCoordinateRegion) -> Void)?
    let onSelect: (Spot, CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        map.showsUserLocation = true
        // Always light mode
        if #available(iOS 13.0, *) { map.overrideUserInterfaceStyle = .light }
        // Standard light configuration
        if #available(iOS 13.0, *) {
            let cfg = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            map.preferredConfiguration = cfg
        }
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "SpotImage")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        
        // Set initial region to user location (or default)
        let initialRegion = LocationManager.shared.getUserRegion()
        map.setRegion(initialRegion, animated: false)
        context.coordinator.initialRegionSet = true
        
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let existing = map.annotations.compactMap { $0 as? SpotPointAnnotation }
        let existingIds = Set(existing.map { $0.spot.id })
        let newIds = Set(spots.map { $0.id })
        
        // Only update if spots actually changed
        if existingIds != newIds {
            map.removeAnnotations(existing)
            let anns: [SpotPointAnnotation] = spots.compactMap { s in
                guard let lat = s.latitude, let lon = s.longitude else { return nil }
                let a = SpotPointAnnotation(spot: s)
                a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                a.title = s.vibeTag
                return a
            }
            map.addAnnotations(anns)
            
            // If we have spots and this is the first load, fit them to view
            // Don't auto-fit if user has already panned/zoomed
            if !anns.isEmpty {
                let spotAnnotations = map.annotations.compactMap { $0 as? SpotPointAnnotation }
                // Only auto-fit if we just added spots and map hasn't been significantly moved
                let currentCenter = map.region.center
                let initialRegion = LocationManager.shared.getUserRegion()
                let distance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                    .distance(from: CLLocation(latitude: initialRegion.center.latitude, longitude: initialRegion.center.longitude))
                
                // If still near initial location (within 10km) or no spots were shown before, fit to spots
                if distance < 10000 || existing.isEmpty {
                    map.showAnnotations(spotAnnotations, animated: false)
                }
            }
        }
    }
    
    func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        // Clean up map resources before deallocation to prevent Metal crashes
        // This ensures Metal textures are properly released before the view is deallocated
        map.delegate = nil
        map.removeAnnotations(map.annotations)
        map.showsUserLocation = false
        map.removeOverlays(map.overlays)
        
        // Hide the map view to stop rendering and give Metal time to finish
        map.isHidden = true
        map.alpha = 0
        
        // Give Metal time to finish current frame before deallocation
        // This prevents the texture from being destroyed while still referenced by command buffer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Additional cleanup if needed - Metal should have finished by now
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusteredSpotMap
        var initialRegionSet = false
        var hasZoomedToUserLocation = false
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChanged?(mapView.region)
        }
        
        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            // Ensure initial region is set after map loads
            if !initialRegionSet {
                let userRegion = LocationManager.shared.getUserRegion()
                mapView.setRegion(userRegion, animated: false)
                initialRegionSet = true
            }
        }
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            // Zoom to user location when it first becomes available (if we haven't already)
            if !hasZoomedToUserLocation && userLocation.location != nil {
                let userRegion = LocationManager.shared.getUserRegion()
                mapView.setRegion(userRegion, animated: true)
                hasZoomedToUserLocation = true
            }
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
