//
//  MapView.swift
//  Spot
//
//  Discovery map. Redesigned to:
//   * use the shared `SharedSpotMap` host (single MKMapView, reused
//     annotations, light mode, no POIs, no MapKit numeric clusters),
//   * render a branded user-location avatar marker (green ring / gold
//     ring for Pro) instead of the default blue dot,
//   * show a stable soft-cluster + individual-pin density model,
//   * fix the IMG_9741 panel overflow bug via `MapSpotPreviewCard` +
//     `MapPanelHeight.clamp`,
//   * fetch viewport spots after pan/zoom settles,
//   * surface a Pro-only filter pill row (hidden for non-Pro), and
//   * emit structured map logs for screen lifecycle, panel state,
//     density transitions, recenter taps, and (debug) memory snapshots.
//

import SwiftUI
import MapKit
import CoreLocation

@MainActor
struct MapView: View {

    // MARK: - State

    @StateObject private var mapVM = MapViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @EnvironmentObject var authVM: AuthViewModel

    @State private var selectedSpot: Spot?
    @State private var selectedSpotCoordinate: CLLocationCoordinate2D?
    @State private var cameraIntent: SharedSpotMapCameraIntent = .none
    @State private var hasPerformedInitialFit: Bool = false
    /// `true` once the camera has been programmatically centered on the
    /// viewer's real location. Subsequent location updates do not re-zoom
    /// (the user can manually pan or tap recenter) — but if we never got a
    /// fix at appear time, the first fix from `.onReceive` triggers it.
    @State private var hasCenteredOnUser: Bool = false
    @State private var lastRegionFromMap: MKCoordinateRegion?

    @State private var filterState: SpotMapFilterState = .empty
    @State private var showVibePicker: Bool = false

    @Environment(\.verticalSizeClass) private var vSize

    init(spots _: [Spot] = []) {}

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    SharedSpotMap(
                        spots: mapVM.visibleSpots,
                        selectedSpotId: selectedSpot?.id,
                        filter: filterState,
                        savedSpotIds: Set(authVM.bookmarkedSpots),
                        likedSpotIds: Set(authVM.likedSpots),
                        followedUserIds: [],
                        allowSoftClusters: false,
                        userMarker: userMarker,
                        suppressDefaultUserDot: true,
                        cameraIntent: cameraIntent,
                        onSelect: { spot, coord in
                            select(
                                spot,
                                coord,
                                mapHeight: geo.size.height,
                                bottomSafeArea: geo.safeAreaInsets.bottom
                            )
                        },
                        onDeselect: { /* tap-on-empty deselect handled by panel close */ },
                        onRegionChanged: { region in
                            lastRegionFromMap = region
                            cameraIntent = .none
                            if FeedFlags.useSupabaseMapRPC {
                                mapVM.loadForRegion(region)
                            }
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)

                    MapControlsOverlay(
                        filterState: filterPillBinding,
                        availableVibeTags: Constants.VibeTags.defaultTags,
                        onOpenVibePicker: { showVibePicker = true },
                        canRecenter: locationManager.userLocation != nil,
                        onRecenter: recenterOnUser,
                        bottomReservedHeight: selectedSpot == nil
                            ? 0
                            : openPanelHeight(in: geo.size, safe: geo.safeAreaInsets.bottom).height
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(true)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomInset(geo: geo)
                }
                .background(Constants.Colors.background)
                .background(Constants.Colors.background.ignoresSafeArea())
                .onAppear { onAppear(geo: geo) }
                .onDisappear { onDisappear() }
                .onReceive(locationManager.$userLocation) { newValue in
                    onUserLocationReceived(newValue)
                }
                .onChange(of: filterState) { _, newValue in
                    syncMapSelectionWithActiveFilter(newValue)
                }
                .sheet(isPresented: $showVibePicker) {
                    MapVibeFilterSheet(
                        state: $filterState,
                        vibeTags: Constants.VibeTags.defaultTags,
                        onClose: { showVibePicker = false }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile(let userId):
                    ProfileView(userId: userId, fromNavigationPush: true)
                        .navigationBarBackButtonHidden(true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Bottom inset (preview card)

    @ViewBuilder
    private func bottomInset(geo: GeometryProxy) -> some View {
        if let spot = selectedSpot {
            let height = openPanelHeight(in: geo.size, safe: geo.safeAreaInsets.bottom)
            MapSpotPreviewCard(
                spot: spot,
                source: "Map",
                onClose: { closePanel() }
            )
            .frame(height: height.height)
            .transition(.move(edge: .bottom))
            .animation(.spring(response: Constants.MapDesign.selectSpringResponse,
                               dampingFraction: Constants.MapDesign.selectSpringDamping),
                       value: selectedSpot != nil)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    /// Computes the safe panel height + emits a `panelHeightClamped` log if
    /// the requested height was reduced by the safe-area / max-fraction
    /// clamp. This is the IMG_9741 fix point.
    private func openPanelHeight(in size: CGSize, safe: CGFloat) -> (height: CGFloat, wasClamped: Bool) {
        // Keep more map visible while still showing enough of the spot card.
        let base: CGFloat = (vSize == .compact) ? size.height * 0.30 : size.height * 0.36
        let clamp = MapPanelHeight.clamp(
            requested: base,
            availableHeight: size.height,
            bottomSafeArea: safe
        )
        if clamp.wasClamped {
            SpotLogger.log(MapViewLogs.panelHeightClamped, details: [
                "requested": Int(base),
                "applied": Int(clamp.height),
                "screen": Int(size.height),
                "bottomSafe": Int(safe)
            ])
        }
        return clamp
    }

    // MARK: - Lifecycle hooks

    private func onAppear(geo: GeometryProxy) {
        SpotLogger.log(MapViewLogs.mapAppeared)
        MemoryDebugLogger.snapshot("map_appear")
        // Re-arm the one-shot auto-center every time the map tab appears.
        hasCenteredOnUser = false
        mapBottomNavDidAppearAndRequestLocationBreakpoint()
        if authVM.userId != nil {
            authVM.refreshUserFlags()
        }
        performInitialFitIfNeeded()

        guard FeedFlags.useSupabaseMapRPC else {
            mapVM.loadAllSpots()
            return
        }

        // Best path: we already have a real or cached location fix →
        // jump straight to it. `userLocation` may have been seeded from
        // the persisted last-known-good fix at LocationManager init,
        // which keeps the map useful on cold starts and on simulators
        // without a configured location.
        if let fix = locationManager.userLocation {
            centerOnUser(coordinate: fix.coordinate, animated: false, source: "appear_fix")
            return
        }

        // No fix yet. Do NOT call `getUserRegion()` here because that
        // returns the Miami fallback and immediately fetches the wrong
        // viewport. Wait for `onUserLocationReceived` to center/fetch as
        // soon as CoreLocation delivers the physical device coordinate.
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            let fallback = LocationManager.shared.getUserRegion(
                radiusInMeters: Constants.MapDesign.initialRadiusMeters
            )
            mapVM.loadForRegion(fallback)
            cameraIntent = .region(fallback, animated: false)
            return
        }

        SpotLogger.log(MapViewLogs.waitingForUserLocation, details: [
            "auth": authStatusLabel(locationManager.authorizationStatus)
        ])
        cameraIntent = .none
    }

    /// BREAKPOINT HERE:
    /// This method is called from `MapView.onAppear`, which is the Map
    /// tab's effective bottom-nav tap entry point. Step into
    /// `LocationManager.requestCurrentLocationForMapTab()` to verify the
    /// CoreLocation one-shot request on a physical device.
    private func mapBottomNavDidAppearAndRequestLocationBreakpoint() {
        SpotLogger.log(MapViewLogs.mapTabLocationRequestStarted, details: [
            "auth": authStatusLabel(locationManager.authorizationStatus),
            "hasUserLocation": locationManager.userLocation != nil
        ])
        locationManager.requestCurrentLocationForMapTab()
    }

    private func onDisappear() {
        SpotLogger.log(MapViewLogs.mapDisappeared)
        MemoryDebugLogger.snapshot("map_disappear")
        locationManager.stopUpdatingLocation()
        hasCenteredOnUser = false
        selectedSpot = nil
        selectedSpotCoordinate = nil
        cameraIntent = .none
        mapVM.clearVisibleSpots()
    }

    /// Fired for the initial published value AND every subsequent fix.
    /// `.onChange(of:)` doesn't fire for the initial value so it would
    /// silently miss the case where `LocationManager` already had a fix
    /// from earlier in the app session.
    private func onUserLocationReceived(_ location: CLLocation?) {
        guard let location else { return }
        guard !hasCenteredOnUser else { return }
        guard selectedSpot == nil else { return }
        centerOnUser(coordinate: location.coordinate, animated: true, source: "received_fix")
    }

    /// Center the discovery camera on `coordinate` and trigger a viewport
    /// fetch in the same beat. Sets `hasCenteredOnUser` so we don't keep
    /// fighting the user once they pan around.
    private func centerOnUser(
        coordinate: CLLocationCoordinate2D,
        animated: Bool,
        source: String
    ) {
        hasCenteredOnUser = true
        let region = MapCameraRegion.neighborhood(
            center: coordinate,
            radiusMeters: Constants.MapDesign.initialNeighborhoodRadiusMeters
        )
        cameraIntent = .region(region, animated: animated)
        if FeedFlags.useSupabaseMapRPC {
            mapVM.loadForRegion(region)
        }
        SpotLogger.log(MapViewLogs.initialFitApplied, details: [
            "source": source,
            "lat": coordinate.latitude,
            "lon": coordinate.longitude,
            "animated": animated
        ])
    }

    // MARK: - Filter binding (Pro gating)

    private var filterPillBinding: Binding<SpotMapFilterState>? {
        guard MapFilterGate.isAvailable(isPro: authVM.isPro) else { return nil }
        return Binding(
            get: { filterState },
            set: { newValue in
                let opening = !filterState.isActive && newValue.isActive
                if opening {
                    SpotLogger.log(MapFilterLogs.filterSheetOpened)
                }
                filterState = newValue
            }
        )
    }

    // MARK: - User marker

    private var userMarker: SpotUserLocationAnnotation? {
        guard let loc = locationManager.userLocation else { return nil }
        return SpotUserLocationAnnotation(
            coordinate: loc.coordinate,
            profileImageURL: authVM.currentUserProfileImageURL,
            username: authVM.currentUserUsername,
            kind: authVM.isPro ? .pro : .regular
        )
    }

    // MARK: - Actions

    private func select(
        _ spot: Spot,
        _ coordinate: CLLocationCoordinate2D,
        mapHeight: CGFloat,
        bottomSafeArea: CGFloat
    ) {
        selectedSpot = spot
        selectedSpotCoordinate = coordinate
        SpotLogger.log(MapViewLogs.homeSheetOpen, details: ["spotId": spot.id ?? "nil"])
        FeedEventService.record(.mapPinTap, spotId: spot.id)
        FeedEventService.record(.detailOpen, spotId: spot.id, metadata: ["surface": "map_panel"])
        let panel = openPanelHeight(
            in: CGSize(width: 0, height: mapHeight),
            safe: bottomSafeArea
        )
        let dynamicLift = max(
            Constants.MapDesign.selectedPinCameraLift,
            panel.height * 0.42
        )
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        cameraIntent = .focus(
            coordinate: coordinate,
            span: span,
            liftPoints: dynamicLift,
            animated: true
        )
    }

    private func closePanel() {
        SpotLogger.log(MapViewLogs.homeSheetClose, details: ["spotId": selectedSpot?.id ?? "nil"])
        selectedSpot = nil
        selectedSpotCoordinate = nil
        // Don't auto-zoom-out — keep user in their current region.
        cameraIntent = .none
    }

    private func recenterOnUser() {
        SpotLogger.log(MapViewLogs.recenterTapped)
        guard let loc = locationManager.userLocation else {
            SpotLogger.log(MapViewLogs.userLocationUnavailable)
            return
        }
        // The recenter button is an explicit user request — re-arm the
        // initial-center latch so any pending location publisher events
        // can't fight the explicit gesture.
        centerOnUser(coordinate: loc.coordinate, animated: true, source: "recenter_button")
    }

    private func performInitialFitIfNeeded() {
        guard !hasPerformedInitialFit else { return }
        hasPerformedInitialFit = true
        SpotLogger.log(MapViewLogs.initialFitApplied, details: [
            "hasUserLocation": locationManager.userLocation != nil,
            "source": "appear_marker"
        ])
    }

    /// Close the preview sheet if the active filter no longer includes the
    /// selected spot (pins are removed from the map, not dimmed).
    private func syncMapSelectionWithActiveFilter(_ filter: SpotMapFilterState) {
        guard let sel = selectedSpot else { return }
        guard filter.isActive else { return }
        let stillMatches = SpotMarkerStyleResolver.matches(
            sel,
            filter: filter,
            savedSpotIds: Set(authVM.bookmarkedSpots),
            likedSpotIds: Set(authVM.likedSpots),
            followedUserIds: []
        )
        if !stillMatches {
            closePanel()
        }
    }

    private func authStatusLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Preview

#Preview("MapView – discovery") {
    let auth = AuthViewModel()
    auth.isPro = false
    return MapView(spots: [
        Spot(id: "1", userId: "u1", username: "eddie",
             imageURL: "https://picsum.photos/seed/3/800/600", vibeTag: "Park",
             latitude: 40.7128, longitude: -74.0060,
             locationName: "NYC", createdAt: Date())
    ])
    .environmentObject(auth)
}
