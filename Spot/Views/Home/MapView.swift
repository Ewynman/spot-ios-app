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

    /// Ignore user-move dismissal until marker-focus / programmatic camera finishes.
    @State private var programmaticCameraSuppressUntil: Date?
    /// Last region snapshot while the drawer is open (updated during suppression; compared after).
    @State private var drawerRegionBaseline: MKCoordinateRegion?
    /// Cancels stale delayed spot-switch updates when markers are tapped quickly.
    @State private var selectionSequence: Int = 0
    /// Discovery drawer: short peek vs raised sheet (full-width, rounded top).
    @State private var mapDrawerDetent: MapSpotDrawerDetent = .peek
    /// Bottom Y of the Pro filter pill row in `mapCanvas` space (`nil` when hidden or not yet laid out).
    @State private var mapFilterPillsMaxY: CGFloat?
    /// Viewport to restore when closing the drawer (from first pin tap in a chain).
    @State private var regionBeforeSpotSelection: MKCoordinateRegion?

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
                        onSelect: { spot, coord, regionAtTap in
                            select(
                                spot,
                                coord,
                                regionAtTap: regionAtTap,
                                geo: geo
                            )
                        },
                        onDeselect: { handleAnnotationDeselectForEmptyMapTap() },
                        onRegionChanged: { region in
                            handleMapRegionChanged(region)
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityIdentifier("map.mapView")
                    .overlay {
                        mapOnboardingTargets
                    }

                    if let spot = selectedSpot {
                        mapDrawerOverlay(
                            spot: spot,
                            geo: geo
                        )
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                        )
                        .zIndex(5)
                    }

                    MapControlsOverlay(
                        filterState: filterPillBinding,
                        availableVibeTags: Constants.VibeTags.defaultTags,
                        onOpenVibePicker: { showVibePicker = true },
                        canRecenter: locationManager.userLocation != nil,
                        onRecenter: recenterOnUser,
                        bottomReservedHeight: selectedSpot == nil
                            ? 0
                            : mapDrawerResolvedHeight(in: geo)
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(true)
                    .zIndex(10)
                }
                .coordinateSpace(name: "mapCanvas")
                .onPreferenceChange(MapFilterPillRowBottomPreferenceKey.self) { value in
                    mapFilterPillsMaxY = value
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
        .accessibilityIdentifier("map.screen")
        .onReceive(NotificationCenter.default.publisher(for: .mainTabReselectSame)) { output in
            guard (output.userInfo?[SpotMainTabNotification.userInfoTabIndexKey] as? Int) == 1 else { return }
            showVibePicker = false
            if selectedSpot != nil {
                dismissSelectedSpot(reason: .tabReselected, animated: true)
            }
        }
    }

    // MARK: - Bottom drawer (root-level overlay, full width)

    @ViewBuilder
    private func mapDrawerOverlay(spot: Spot, geo: GeometryProxy) -> some View {
        let height = mapDrawerResolvedHeight(in: geo)
        MapSpotPreviewCard(
            spot: spot,
            source: "Map",
            onClose: { closePanel() },
            drawerDetent: $mapDrawerDetent
        )
        .id(spot.id ?? spot.safeId)
        .measure(target: .mapMarkerPreview)
        .frame(width: geo.size.width)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: height)
        .clipped()
        .animation(
            .spring(
                response: Constants.MapDesign.selectSpringResponse,
                dampingFraction: Constants.MapDesign.selectSpringDamping
            ),
            value: selectedSpot?.id
        )
        .animation(
            .spring(
                response: Constants.MapDesign.selectSpringResponse,
                dampingFraction: Constants.MapDesign.selectSpringDamping
            ),
            value: mapDrawerDetent
        )
    }

    /// Peek / expanded heights, capped so the drawer stops ~`mapDrawerGapBelowFilterPills` below the filter pills.
    private func mapDrawerResolvedHeight(in geo: GeometryProxy) -> CGFloat {
        let safe = geo.safeAreaInsets.bottom
        let ceiling = drawerMaxHeightBelowFilterPills(in: geo)
        switch mapDrawerDetent {
        case .peek:
            let requested = openPanelHeight(in: geo.size, safe: safe).height
            return max(Constants.MapDesign.panelMinHeight, min(requested, ceiling))
        case .expanded:
            let requested = expandedMapDrawerHeight(in: geo.size, bottomSafeArea: safe)
            return max(Constants.MapDesign.panelMinHeight, min(requested, ceiling))
        }
    }

    /// Max drawer height from bottom padding up to `gap` below the measured filter row (or a safe fallback when non‑Pro).
    private func drawerMaxHeightBelowFilterPills(in geo: GeometryProxy) -> CGFloat {
        let bottomPad = max(geo.safeAreaInsets.bottom, 8)
        let gap = Constants.MapDesign.mapDrawerGapBelowFilterPills
        let pillsBottom = filterPillsBottomY(in: geo)
        let topOfDrawer = pillsBottom + gap
        return max(0, geo.size.height - topOfDrawer - bottomPad)
    }

    private func filterPillsBottomY(in geo: GeometryProxy) -> CGFloat {
        if let y = mapFilterPillsMaxY, y > 1 { return y }
        // Non–Pro (no pill row): approximate top chrome so the drawer still doesn’t run under the status area.
        return geo.safeAreaInsets.top + 52
    }

    /// Peek height used for pin camera lift — matches capped peek drawer.
    private func peekPanelHeightForCameraLift(in geo: GeometryProxy) -> CGFloat {
        let safe = geo.safeAreaInsets.bottom
        let requested = openPanelHeight(in: geo.size, safe: safe).height
        let ceiling = drawerMaxHeightBelowFilterPills(in: geo)
        return max(Constants.MapDesign.panelMinHeight, min(requested, ceiling))
    }

    private func expandedMapDrawerHeight(in size: CGSize, bottomSafeArea: CGFloat) -> CGFloat {
        let topReveal: CGFloat = 8
        let usable = size.height - bottomSafeArea - topReveal
        let maxDrawer = size.height * Constants.MapDesign.panelMaxScreenFraction
        return max(Constants.MapDesign.panelMinHeight, min(usable, maxDrawer))
    }

    private var mapOnboardingTargets: some View {
        GeometryReader { geo in
            ZStack {
                if locationManager.userLocation != nil {
                    Color.clear
                        .frame(width: 74, height: 74)
                        .clipShape(Circle())
                        .measure(target: .mapUserLocation)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                Color.clear
                    .frame(width: min(190, geo.size.width * 0.56), height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .measure(target: .mapMarkers)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        mapFilterPillsMaxY = nil
        if selectedSpot != nil {
            dismissSelectedSpot(reason: .tabLeft, animated: false)
        }
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
        mapVM.loadForRegion(region)
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

    private var isProgrammaticCameraSuppressActive: Bool {
        guard let until = programmaticCameraSuppressUntil else { return false }
        return Date() < until
    }

    private func scheduleProgrammaticCameraSuppression() {
        programmaticCameraSuppressUntil = Date().addingTimeInterval(
            MapDiscoveryDrawerPolicy.programmaticCameraSuppressionSeconds
        )
    }

    private func select(
        _ spot: Spot,
        _ coordinate: CLLocationCoordinate2D,
        regionAtTap: MKCoordinateRegion,
        geo: GeometryProxy
    ) {
        /// Snapshot restore target only when opening from “no drawer” — keeps the original viewport through pin switches.
        let hadDrawerOpen = selectedSpot != nil
        let newId = spot.id
        let oldId = selectedSpot?.id
        let isSwitch = oldId != nil && newId != nil && oldId != newId

        if isSwitch {
            SpotLogger.log(MapViewLogs.mapSpotSwitchAnimated, details: [
                "fromSpotId": oldId ?? "nil",
                "toSpotId": newId ?? "nil"
            ])
            selectionSequence += 1
            let seq = selectionSequence
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSpot = nil
                selectedSpotCoordinate = nil
                drawerRegionBaseline = nil
                mapDrawerDetent = .peek
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard seq == selectionSequence else { return }
                applyMarkerSelection(
                    spot,
                    coordinate,
                    regionAtTap: regionAtTap,
                    geo: geo,
                    captureRestoreRegion: !hadDrawerOpen
                )
            }
        } else {
            selectionSequence += 1
            applyMarkerSelection(
                spot,
                coordinate,
                regionAtTap: regionAtTap,
                geo: geo,
                captureRestoreRegion: !hadDrawerOpen
            )
        }
    }

    private func applyMarkerSelection(
        _ spot: Spot,
        _ coordinate: CLLocationCoordinate2D,
        regionAtTap: MKCoordinateRegion,
        geo: GeometryProxy,
        captureRestoreRegion: Bool
    ) {
        if captureRestoreRegion {
            regionBeforeSpotSelection = regionAtTap
        }
        withAnimation(
            .spring(
                response: Constants.MapDesign.selectSpringResponse,
                dampingFraction: Constants.MapDesign.selectSpringDamping
            )
        ) {
            selectedSpot = spot
            selectedSpotCoordinate = coordinate
            mapDrawerDetent = .peek
        }
        drawerRegionBaseline = nil
        scheduleProgrammaticCameraSuppression()

        SpotLogger.log(MapViewLogs.homeSheetOpen, details: ["spotId": spot.id ?? "nil"])
        FeedEventService.record(.mapPinTap, spotId: spot.id)
        FeedEventService.record(.detailOpen, spotId: spot.id, metadata: ["surface": "map_panel"])
        let panelHeight = peekPanelHeightForCameraLift(in: geo)
        let dynamicLift = max(
            Constants.MapDesign.selectedPinCameraLift,
            panelHeight * 0.42
        )
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        cameraIntent = .focus(
            coordinate: coordinate,
            span: span,
            liftPoints: dynamicLift,
            animated: true
        )
    }

    private func handleMapRegionChanged(_ region: MKCoordinateRegion) {
        lastRegionFromMap = region
        cameraIntent = .none
        mapVM.loadForRegion(region)

        guard selectedSpot != nil else {
            drawerRegionBaseline = nil
            return
        }

        if isProgrammaticCameraSuppressActive {
            drawerRegionBaseline = region
            return
        }

        if let base = drawerRegionBaseline {
            if MapDiscoveryDrawerPolicy.regionsMeaningfullyDiffer(base, region) {
                dismissSelectedSpot(reason: .mapMoved, animated: true)
            }
        } else {
            drawerRegionBaseline = region
        }
    }

    private func handleAnnotationDeselectForEmptyMapTap() {
        let priorId = selectedSpot?.id
        guard let priorId else { return }
        Task { @MainActor in
            await Task.yield()
            guard selectedSpot?.id == priorId else { return }
            dismissSelectedSpot(reason: .emptyMapTap, animated: true)
        }
    }

    private func dismissSelectedSpot(
        reason: MapDrawerDismissReason,
        animated: Bool = true
    ) {
        guard let spot = selectedSpot else { return }
        let spotId = spot.id ?? spot.safeId
        SpotLogger.log(MapViewLogs.mapDrawerDismissed, details: [
            "reason": reason.rawValue,
            "spotId": spotId
        ])
        SpotLogger.log(MapViewLogs.homeSheetClose, details: [
            "spotId": spotId,
            "reason": reason.rawValue
        ])
        let restoreRegion = regionBeforeSpotSelection
        let restoreViewport = shouldRestoreViewportAfterDismiss(reason: reason)
        let apply = {
            self.selectedSpot = nil
            self.selectedSpotCoordinate = nil
            self.drawerRegionBaseline = nil
            self.programmaticCameraSuppressUntil = nil
            self.mapDrawerDetent = .peek
            self.regionBeforeSpotSelection = nil
            if restoreViewport, let region = restoreRegion {
                self.cameraIntent = .region(region, animated: true)
                self.scheduleProgrammaticCameraSuppression()
            } else {
                self.cameraIntent = .none
            }
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.18), apply)
        } else {
            apply()
        }
    }

    /// After dismiss, zoom back to the pre-spot viewport unless the user already moved the map (e.g. pan dismiss).
    private func shouldRestoreViewportAfterDismiss(reason: MapDrawerDismissReason) -> Bool {
        switch reason {
        case .mapMoved:
            return false
        default:
            return true
        }
    }

    private func closePanel() {
        dismissSelectedSpot(reason: .closeButton, animated: true)
    }

    private func recenterOnUser() {
        SpotLogger.log(MapViewLogs.recenterTapped)
        guard let loc = locationManager.userLocation else {
            SpotLogger.log(MapViewLogs.userLocationUnavailable)
            return
        }
        if selectedSpot != nil {
            dismissSelectedSpot(reason: .mapMoved, animated: false)
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
            dismissSelectedSpot(reason: .selectedSpotNoLongerVisible, animated: true)
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
