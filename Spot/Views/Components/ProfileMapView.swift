//
//  ProfileMapView.swift
//  Spot
//
//  Profile map. Shares the redesigned marker visual language with the
//  discovery map (`SharedSpotMap` host) but keeps profile-specific data
//  rules:
//
//   * No discovery RPC. Renders only the profile owner's pre-loaded spots.
//   * No viewer-location avatar marker (and no Apple blue dot).
//   * Fits all profile pins on open and on dismiss of the preview card.
//   * Preserves existing parent callbacks: onSpotTap, onDeleteSpot,
//     onCollapseChange.
//

import SwiftUI
import MapKit
import CoreLocation

struct ProfileMapView: View {
    let spots: [Spot]
    /// Lift (in points) used to keep a selected pin visible above the
    /// preview panel. Mirrors prior `markerOffset` parameter for source
    /// compatibility.
    var markerOffset: CGFloat = Constants.MapDesign.selectedPinCameraLift

    @State private var selectedSpot: Spot?
    @State private var cameraIntent: SharedSpotMapCameraIntent = .fitAll(animated: false)
    @State private var hasFitInitialPins: Bool = false

    @Environment(\.verticalSizeClass) private var vSize
    private var onSpotTap: ((Spot) -> Void)?
    private var onDeleteSpot: ((Spot) -> Void)?
    private var onCollapseChange: ((Bool) -> Void)?

    init(
        spots: [Spot],
        onSpotTap: ((Spot) -> Void)? = nil,
        onDeleteSpot: ((Spot) -> Void)? = nil,
        onCollapseChange: ((Bool) -> Void)? = nil
    ) {
        self.spots = spots
        self.onSpotTap = onSpotTap
        self.onDeleteSpot = onDeleteSpot
        self.onCollapseChange = onCollapseChange
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                SharedSpotMap(
                    spots: spots,
                    selectedSpotId: selectedSpot?.id,
                    filter: .empty,
                    savedSpotIds: [],
                    likedSpotIds: [],
                    followedUserIds: [],
                    allowSoftClusters: true,
                    userMarker: nil,
                    suppressDefaultUserDot: true,
                    cameraIntent: cameraIntent,
                    onSelect: { spot, coord in select(spot, coord, mapHeight: geo.size.height) },
                    onDeselect: { /* card close drives deselect */ },
                    onRegionChanged: { _ in
                        cameraIntent = .none
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                insetContent(geo: geo)
            }
            .onAppear {
                if !hasFitInitialPins {
                    hasFitInitialPins = true
                    cameraIntent = .fitAll(animated: false)
                }
            }
            .onChange(of: spotsSignature) { _, _ in
                if selectedSpot == nil {
                    cameraIntent = .fitAll(animated: true)
                }
            }
            .onDisappear {
                selectedSpot = nil
                cameraIntent = .none
            }
        }
        .toolbar(selectedSpot != nil ? .hidden : .visible, for: .tabBar)
        .background(Constants.Colors.background.ignoresSafeArea())
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private func insetContent(geo: GeometryProxy) -> some View {
        if let spot = selectedSpot {
            let height = panelHeight(in: geo.size, safe: geo.safeAreaInsets.bottom)
            MapSpotPreviewCard(
                spot: spot,
                allowDelete: true,
                source: "ProfileMap",
                onBackToAll: { backToAll() },
                onClose: { closePanel() },
                onDelete: { onDeleteSpot?(spot) }
            )
            .frame(height: height.height)
            .transition(.move(edge: .bottom))
            .zIndex(10)
            .animation(
                .spring(response: Constants.MapDesign.selectSpringResponse,
                        dampingFraction: Constants.MapDesign.selectSpringDamping),
                value: selectedSpot != nil
            )
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func panelHeight(in size: CGSize, safe: CGFloat) -> (height: CGFloat, wasClamped: Bool) {
        let base: CGFloat = (vSize == .compact) ? size.height * 0.40 : 320
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
                "bottomSafe": Int(safe),
                "surface": "ProfileMap"
            ])
        }
        return clamp
    }

    // MARK: - Actions

    private func select(_ spot: Spot, _ coordinate: CLLocationCoordinate2D, mapHeight _: CGFloat) {
        selectedSpot = spot
        onSpotTap?(spot)
        onCollapseChange?(true)
        SpotLogger.log(MapViewLogs.homeSheetOpen, details: [
            "surface": "ProfileMap",
            "spotId": spot.id ?? "nil"
        ])
        let span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        cameraIntent = .focus(
            coordinate: coordinate,
            span: span,
            liftPoints: markerOffset,
            animated: true
        )
    }

    private func backToAll() {
        SpotLogger.log(MapViewLogs.homeSheetClose, details: [
            "surface": "ProfileMap",
            "reason": "back_to_all"
        ])
        selectedSpot = nil
        cameraIntent = .fitAll(animated: true)
        onCollapseChange?(false)
    }

    private func closePanel() {
        SpotLogger.log(MapViewLogs.homeSheetClose, details: [
            "surface": "ProfileMap",
            "reason": "x_button"
        ])
        selectedSpot = nil
        cameraIntent = .fitAll(animated: true)
        onCollapseChange?(false)
    }

    private var spotsSignature: String {
        spots.compactMap { $0.id }.joined(separator: ",")
    }
}

// MARK: - Preview

#Preview {
    ProfileMapView(spots: [
        Spot(id: "1", userId: "u1", username: "eddie",
             imageURL: "https://picsum.photos/seed/1/800/600", vibeTag: "View",
             latitude: 37.7749, longitude: -122.4194,
             locationName: "San Francisco", createdAt: Date()),
        Spot(id: "2", userId: "u1", username: "eddie",
             imageURL: "https://picsum.photos/seed/2/800/600", vibeTag: "Coffee",
             latitude: 34.0522, longitude: -118.2437,
             locationName: "Los Angeles", createdAt: Date())
    ])
    .environmentObject(AuthViewModel())
}
