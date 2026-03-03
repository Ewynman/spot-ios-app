//
//  ProfileMapView.swift
//  Spot
//

import SwiftUI
import MapKit

struct ProfileMapView: View {
    let spots: [Spot]
    var markerOffset: CGFloat = 100

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedSpot: Spot?

    @Environment(\.verticalSizeClass) private var vSize
    private var onSpotTap: ((Spot) -> Void)?
    private var onCollapseChange: ((Bool) -> Void)?

    // MARK: - Init
    init(spots: [Spot], onSpotTap: ((Spot) -> Void)? = nil, onCollapseChange: ((Bool) -> Void)? = nil) {
        self.spots = spots
        self.onSpotTap = onSpotTap
        self.onCollapseChange = onCollapseChange

        if let region = Self.regionToFit(spots) {
            _cameraPosition = State(initialValue: .region(region))
        } else {
            _cameraPosition = State(
                initialValue: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    )
                )
            )
        }
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Map kept alive (we never animate its height)
                InnerProfileSpotMap(
                    region: Binding(
                        get: {
                            extractRegion(from: cameraPosition)
                        },
                        set: { newRegion in
                            cameraPosition = .region(newRegion)
                        }
                    ),
                    spots: spots,
                    selectedSpot: selectedSpot,
                    onSelect: { spot, coord in
                        select(spot, coord, geo.size) // <- size-aware so we can offset in points
                    }
                )
            }
            // Split layout via bottom inset (prevents Metal-layer crashes and keeps map interactive)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                insetContent(height: openPanelHeight(in: geo.size))
            }
            // Refit whenever the set of spot IDs changes (but only if no spot is selected)
            .onChange(of: spotsSignature) { _, _ in
                if selectedSpot == nil { zoomToFitAllPins() }
            }
            .onAppear {
                if selectedSpot == nil { zoomToFitAllPins() }
            }
            // Prevent zoom-out when selecting a spot
            .onChange(of: selectedSpot) { oldValue, newValue in
                // When a spot is selected, ensure we don't zoom out
                // The select() function handles zooming in
                if newValue != nil && oldValue == nil {
                    // Spot just selected - select() will handle zoom
                } else if newValue == nil && oldValue != nil {
                    // Spot deselected - zoom back to fit all
                    zoomToFitAllPins()
                }
            }
            .onDisappear {
                // Clear selected spot to ensure map resources are released before navigation
                // This prevents Metal crashes when navigating away
                selectedSpot = nil
            }
        }
        // Hide the system Tab Bar while the panel is open so it can't intercept taps.
        .toolbar(selectedSpot != nil ? .hidden : .visible, for: .tabBar)

        // Paint the screen AND the *top* safe-area (status/notch) with your app background.
        .background(Constants.Colors.background.ignoresSafeArea())
    }

    // MARK: - Inset (Bottom Panel)
    @ViewBuilder
    private func insetContent(height: CGFloat) -> some View {
        if let spot = selectedSpot {
            ProfileFullBleedPanel(
                spot: spot,
                onBackToAll: { backToAll() },
                onClose: { closePanel() }
            )
            .frame(height: height)
            .transition(.move(edge: .bottom))
            .zIndex(10) // ensure above map/tab bar
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedSpot != nil)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    // MARK: - Panel sizing
    // Smaller panel for profile map - shows spot card below marker, not full screen
    private func openPanelHeight(in size: CGSize) -> CGFloat {
        // Fixed height for spot card - enough to show the card but not take over the screen
        return 320
    }

    // MARK: - Actions
    private func select(_ spot: Spot, _ coordinate: CLLocationCoordinate2D, _ viewSize: CGSize) {
        selectedSpot = spot
        onSpotTap?(spot)
        onCollapseChange?(true)

        // Get current region to compare spans
        let currentRegion = extractRegion(from: cameraPosition)
        let currentSpan = currentRegion.span.latitudeDelta
        
        // Use a tight zoom span - much smaller than typical "fit all" view
        // This ensures we always zoom IN when selecting a spot
        let targetSpan = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        
        // Only zoom in if current span is larger (more zoomed out)
        let finalSpan = currentSpan < targetSpan.latitudeDelta ? 
            MKCoordinateSpan(latitudeDelta: currentSpan * 0.5, longitudeDelta: currentSpan * 0.5) : 
            targetSpan
        
        let baseRegion = MKCoordinateRegion(center: coordinate, span: finalSpan)

        // Degrees of latitude per rendered point at the chosen zoom
        let latPerPoint = baseRegion.span.latitudeDelta / max(viewSize.height, 1)

        // Positive markerOffset lifts the pin UP visually → move the *camera* SOUTH
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - latPerPoint * markerOffset,
            longitude: coordinate.longitude
        )

        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            cameraPosition = .region(MKCoordinateRegion(center: adjustedCenter, span: finalSpan))
        }
    }

    private func backToAll() {
        selectedSpot = nil
        zoomToFitAllPins()
        onCollapseChange?(false)
    }

    private func closePanel() {
        selectedSpot = nil
        zoomToFitAllPins()
        onCollapseChange?(false)
    }

    private var spotsSignature: String {
        spots.compactMap { $0.id }.joined(separator: ",")
    }

    private func zoomToFitAllPins() {
        guard let region = Self.regionToFit(spots) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            cameraPosition = .region(region)
        }
    }

    // Helper function to extract region from MapCameraPosition
    // Uses Mirror reflection to extract the region value since pattern matching doesn't work
    private func extractRegion(from position: MapCameraPosition) -> MKCoordinateRegion {
        let mirror = Mirror(reflecting: position)
        for child in mirror.children {
            if let region = child.value as? MKCoordinateRegion {
                return region
            }
        }
        // Fallback: calculate region from spots if available, otherwise use default
        if let region = Self.regionToFit(spots) {
            return region
        }
        // Last resort: default region
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    private static func regionToFit(_ spots: [Spot]) -> MKCoordinateRegion? {
        let coords: [CLLocationCoordinate2D] = spots.compactMap {
            guard let lat = $0.latitude, let lon = $0.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard let first = coords.first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = Swift.min(minLat, c.latitude); maxLat = Swift.max(maxLat, c.latitude)
            minLon = Swift.min(minLon, c.longitude); maxLon = Swift.max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Padding + minimum span so it never zooms absurdly tight
        let latDelta = max(0.02, (maxLat - minLat) * 1.3)
        let lonDelta = max(0.02, (maxLon - minLon) * 1.3)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

#Preview {
    let spots = [
        Spot(id: "1", userId: "u1", username: "eddie", imageURL: "https://picsum.photos/seed/1/800/600", vibeTag: "View", latitude: 37.7749, longitude: -122.4194, locationName: "San Francisco", createdAt: Date()),
        Spot(id: "2", userId: "u2", username: "sam", imageURL: "https://picsum.photos/seed/2/800/600", vibeTag: "Coffee", latitude: 34.0522, longitude: -118.2437, locationName: "Los Angeles", createdAt: Date())
    ]
    return ProfileMapView(spots: spots)
}

// MARK: - UIKit-backed Map (for better Metal cleanup control)
private struct InnerProfileSpotMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let spots: [Spot]
    let selectedSpot: Spot?
    let onSelect: (Spot, CLLocationCoordinate2D) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false
        map.overrideUserInterfaceStyle = .light
        
        if #available(iOS 13.0, *) {
            let cfg = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            map.preferredConfiguration = cfg
        }
        
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "SpotImage")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        
        // Add initial annotations if spots are available
        let initialAnns: [ProfileSpotPointAnnotation] = spots.compactMap { s in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            let a = ProfileSpotPointAnnotation(spot: s)
            a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            a.title = s.vibeTag
            return a
        }
        if !initialAnns.isEmpty {
            map.addAnnotations(initialAnns)
            // Fit map to show all annotations
            map.showAnnotations(initialAnns, animated: false)
        } else {
            // Set initial region if no spots
            map.setRegion(region, animated: false)
        }
        
        return map
    }
    
    func updateUIView(_ map: MKMapView, context: Context) {
        // Update annotations
        let existing = map.annotations.compactMap { $0 as? ProfileSpotPointAnnotation }
        let existingIds = Set(existing.map { $0.spot.id })
        let newIds = Set(spots.map { $0.id })
        
        // Always update if IDs don't match or if we have spots but no annotations
        // BUT: Don't update annotations if a spot is currently selected (to prevent zoom-out)
        if (existingIds != newIds || (existing.isEmpty && !spots.isEmpty)) && selectedSpot == nil {
            map.removeAnnotations(existing)
            let anns: [ProfileSpotPointAnnotation] = spots.compactMap { s in
                guard let lat = s.latitude, let lon = s.longitude else { return nil }
                let a = ProfileSpotPointAnnotation(spot: s)
                // Ensure coordinate is set correctly from spot data
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                a.coordinate = coord
                a.title = s.vibeTag
                return a
            }
            if !anns.isEmpty {
                map.addAnnotations(anns)
                // Only fit all annotations if no spot is selected
                map.showAnnotations(anns, animated: !existing.isEmpty)
            }
        }
        
        // Update scale effect for selected spot
        for annotation in map.annotations {
            if let ann = annotation as? ProfileSpotPointAnnotation,
               let view = map.view(for: ann) {
                if let selectedId = selectedSpot?.id, selectedId == ann.spot.id {
                    view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                } else {
                    view.transform = .identity
                }
            }
        }
        
        // Update camera position - always respect region changes (including when spot is selected)
        // This is critical: when a spot is selected, we need to zoom in, not out
        if selectedSpot != nil {
            // When a spot is selected, always update the region to zoom in (don't check distance)
            // This ensures we zoom to the selected spot even if the distance check would prevent it
            map.setRegion(region, animated: true)
        } else {
            // When no spot is selected, only update if significantly different (more than 100m)
            let currentCenter = map.region.center
            let distance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
            
            if distance > 100 {
                map.setRegion(region, animated: false)
            }
        }
    }
    
    func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        // Clean up before deallocation to prevent Metal crashes
        map.delegate = nil
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)
        
        // Hide the map view to stop rendering
        map.isHidden = true
        map.alpha = 0
        
        // Give Metal time to finish current frame before deallocation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Cleanup complete - Metal should have finished by now
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: InnerProfileSpotMap
        
        init(_ parent: InnerProfileSpotMap) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(Constants.Colors.primary)
                return view
            }
            
            guard let ann = annotation as? ProfileSpotPointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "SpotImage", for: ann)
            // No clustering for profile map - show individual markers
            view.clusteringIdentifier = nil
            view.canShowCallout = false
            
            // Custom image marker
            if let img = UIImage(named: "green_marker") {
                view.image = img
                view.centerOffset = CGPoint(x: 0, y: -img.size.height * 0.4)
            } else {
                // Fallback to a tinted marker if asset missing
                let marker = MKMarkerAnnotationView(annotation: ann, reuseIdentifier: nil)
                // No clustering for profile map
                marker.clusteringIdentifier = nil
                marker.markerTintColor = UIColor(Constants.Colors.primary)
                return marker
            }
            
            // Scale effect for selected spot
            if let selectedId = parent.selectedSpot?.id, selectedId == ann.spot.id {
                view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            } else {
                view.transform = .identity
            }
            
            return view
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // No clustering, so no cluster handling needed
            guard let ann = view.annotation as? ProfileSpotPointAnnotation else { return }
            // Use the annotation's actual coordinate
            let annotationCoordinate = ann.coordinate
            // Call onSelect which will update cameraPosition and trigger region update
            // Don't set region directly here - let the select() function handle it with proper offset
            parent.onSelect(ann.spot, annotationCoordinate)
        }
    }
}

private final class ProfileSpotPointAnnotation: MKPointAnnotation {
    let spot: Spot
    init(spot: Spot) { self.spot = spot; super.init() }
}

// MARK: - Full-bleed bottom panel (no corners/shadows) with header like your mock
private struct ProfileFullBleedPanel: View {
    let spot: Spot
    var onBackToAll: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with grabber, "< Back to all spots" (left) and X (right)
            ZStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Constants.Colors.primary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 32)

            // Your existing card (like/bookmark now tappable because tab bar is hidden)
            SpotCard(
                spot: spot,
                showUserInfo: true,
                userId: nil,
                onDelete: { },
                source: "ProfileMap"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Constants.Colors.background)
        .ignoresSafeArea()
    }
}
