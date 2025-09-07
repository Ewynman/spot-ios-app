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

    // MARK: - Init
    init(spots: [Spot], onSpotTap: ((Spot) -> Void)? = nil) {
        self.spots = spots
        _ = onSpotTap // silence unused param for now

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
                    position: $cameraPosition,
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
            // Refit whenever the set of spot IDs changes
            .onChange(of: spotsSignature) { _, _ in
                if selectedSpot == nil { zoomToFitAllPins() }
            }
            .onAppear {
                if selectedSpot == nil { zoomToFitAllPins() }
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
    private func openPanelHeight(in size: CGSize) -> CGFloat {
        let base: CGFloat = (vSize == .compact) ? size.height * 0.40 : size.height * 0.55
        return min(max(base, 280), size.height * 0.92)
    }

    // MARK: - Actions
    private func select(_ spot: Spot, _ coordinate: CLLocationCoordinate2D, _ viewSize: CGSize) {
        selectedSpot = spot

        // Base zoom you already use
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let baseRegion = MKCoordinateRegion(center: coordinate, span: span)

        // Degrees of latitude per rendered point at the chosen zoom
        let latPerPoint = baseRegion.span.latitudeDelta / max(viewSize.height, 1)

        // Positive markerOffset lifts the pin UP visually → move the *camera* SOUTH
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - latPerPoint * markerOffset,
            longitude: coordinate.longitude
        )

        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            cameraPosition = .region(MKCoordinateRegion(center: adjustedCenter, span: span))
        }
    }

    private func backToAll() {
        selectedSpot = nil
        zoomToFitAllPins()
    }

    private func closePanel() {
        selectedSpot = nil
        zoomToFitAllPins()
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

// MARK: - Extracted Map (fast to type-check)
private struct InnerProfileSpotMap: View {
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
        // Force LIGHT map; no user puck because we don't add UserAnnotation()
        .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        // Fill vertical space and render under top safe area to avoid gaps.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func coordinate(for spot: Spot) -> CLLocationCoordinate2D? {
        guard let lat = spot.latitude, let lon = spot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
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
