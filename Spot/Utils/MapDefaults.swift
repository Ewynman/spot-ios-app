//
//  MapDefaults.swift
//  Spot
//
//  Centralised, deterministic map fallback regions used when CoreLocation
//  cannot give us a real fix (denied / restricted / Location Services off /
//  unavailable / one-shot timeout). The continental United States span is
//  the App Review-mandated fallback so the discovery map always opens with
//  a useful viewport — even with location permission denied.
//
//  See `docs/engineering/permissions.md` for the policy.
//

import CoreLocation
import MapKit

enum MapDefaults {
    /// Approximate geographic centre of the contiguous United States used
    /// when no real location is available. Source: USGS National Atlas /
    /// NOAA — the same coordinate cited in the App Review remediation PRD.
    static let continentalUSCenter = CLLocationCoordinate2D(
        latitude: 39.8283,
        longitude: -98.5795
    )

    /// Wide span that comfortably covers the lower 48 states. Tuned so the
    /// fallback map opens at a useful zoom on small phones without showing
    /// blank ocean tiles around the edges.
    static let continentalUSSpan = MKCoordinateSpan(
        latitudeDelta: 24.0,
        longitudeDelta: 58.0
    )

    /// Region constant exposed to map view models. Fully deterministic so
    /// `MapInitialRegionResolver`-style helpers can be unit tested without
    /// any CoreLocation mocking.
    static let continentalUSRegion = MKCoordinateRegion(
        center: continentalUSCenter,
        span: continentalUSSpan
    )
}
