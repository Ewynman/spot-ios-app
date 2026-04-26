import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var pendingOneShotLocationRequest = false

    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Miami Beach coordinates as default
    static let defaultLocation = CLLocation(
        latitude: 25.7907,
        longitude: -80.1300
    )

    /// Most-recent good fix, persisted across app sessions. Used by the
    /// map to pre-paint a useful region while CoreLocation acquires a
    /// fresh fix (or while running on a simulator without a configured
    /// location).
    private static let cachedLocationKey = "spot.location.lastKnownGood"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // Update location when user moves 10 meters
        // Seed the in-memory cache from disk if we have a previous fix.
        if let cached = Self.loadCachedLocation() {
            userLocation = cached
        }
        // Pick up whatever the system already authorized us for.
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationPermission() {
        SpotLogger.log(LocationManagerLogs.authorizationRequested)
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        SpotLogger.log(LocationManagerLogs.startUpdatingLocation, details: [
            "auth": Self.label(for: manager.authorizationStatus),
            "hasCachedLocation": userLocation != nil
        ])
        // Physical-device fast path: CoreLocation often has a recent fix
        // already cached on the manager. Seed it immediately so MapView
        // doesn't sit in a nil-location state while waiting for delegate
        // callbacks.
        if userLocation == nil, let immediate = manager.location {
            userLocation = immediate
            Self.cache(immediate)
            SpotLogger.log(LocationManagerLogs.locationFixReceived, details: [
                "lat": immediate.coordinate.latitude,
                "lon": immediate.coordinate.longitude,
                "accuracy": immediate.horizontalAccuracy,
                "source": "manager.location"
            ])
        }
        manager.startUpdatingLocation()
        applySimulatorOverrideIfNeeded()
    }

    func stopUpdatingLocation() {
        SpotLogger.log(LocationManagerLogs.stopUpdatingLocation)
        manager.stopUpdatingLocation()
    }

    /// One-call bootstrap: if permission hasn't been asked, ask. If we're
    /// already authorized, just start updating. Idempotent — safe to call
    /// from any screen's `onAppear`.
    func ensureAuthorizationAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            requestLocationPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        case .denied, .restricted:
            // Nothing we can do here; surface state so MapView can show
            // its CTA. We *still* try to start (CL is a no-op, but the
            // call is harmless and keeps lifecycle logs consistent).
            startUpdatingLocation()
        @unknown default:
            startUpdatingLocation()
        }
    }

    /// Entry point used by the Map tab. This is the place to breakpoint
    /// when verifying "tap Map in the bottom nav -> ask CoreLocation for
    /// the user's current coordinate".
    func requestCurrentLocationForMapTab() {
        SpotLogger.log(LocationManagerLogs.oneShotLocationRequested, details: [
            "auth": Self.label(for: manager.authorizationStatus),
            "hasExistingLocation": userLocation != nil
        ])

        switch manager.authorizationStatus {
        case .notDetermined:
            pendingOneShotLocationRequest = true
            requestLocationPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
            manager.requestLocation()
        case .denied, .restricted:
            startUpdatingLocation()
        @unknown default:
            startUpdatingLocation()
        }
    }

    // Get region centered on user's location with specified radius in meters
    func getUserRegion(radiusInMeters: Double = 5000) -> MKCoordinateRegion {
        let location = userLocation ?? Self.defaultLocation
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusInMeters,
            longitudinalMeters: radiusInMeters
        )
        return region
    }

    // Get region that encompasses all spots
    func getRegionForSpots(_ spots: [Spot], defaultRadius: Double = 5000) -> MKCoordinateRegion {
        guard !spots.isEmpty else {
            // Default to Miami Beach if no spots
            return MKCoordinateRegion(
                center: Self.defaultLocation.coordinate,
                latitudinalMeters: defaultRadius,
                longitudinalMeters: defaultRadius
            )
        }

        let validCoordinates = spots.compactMap { spot -> CLLocationCoordinate2D? in
            guard let lat = spot.latitude, let lng = spot.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        guard !validCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: Self.defaultLocation.coordinate,
                latitudinalMeters: defaultRadius,
                longitudinalMeters: defaultRadius
            )
        }

        // Calculate the bounding box
        let minLat = validCoordinates.map { $0.latitude }.min()!
        let maxLat = validCoordinates.map { $0.latitude }.max()!
        let minLng = validCoordinates.map { $0.longitude }.min()!
        let maxLng = validCoordinates.map { $0.longitude }.max()!

        // Calculate center
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        // Calculate span with some padding
        let latDelta = max(0.01, (maxLat - minLat) * 1.5)
        let lngDelta = max(0.01, (maxLng - minLng) * 1.5)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latDelta,
                longitudeDelta: lngDelta
            )
        )
    }

    // MARK: - Persistence

    /// Persist the most recent fix so a fresh launch (or a simulator
    /// without a configured location) can still paint a sensible region.
    private static func cache(_ location: CLLocation) {
        let dict: [String: Double] = [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude
        ]
        UserDefaults.standard.set(dict, forKey: cachedLocationKey)
    }

    private static func loadCachedLocation() -> CLLocation? {
        guard let dict = UserDefaults.standard.dictionary(forKey: cachedLocationKey),
              let lat = dict["lat"] as? Double,
              let lon = dict["lon"] as? Double else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: - Debug helpers

    /// In simulator-DEBUG builds, seed `userLocation` immediately so the
    /// map opens at a sensible location even when:
    ///   * the simulator hasn't been configured with a custom location,
    ///   * the scheme's `LocationScenarioReference` (GPX) didn't apply,
    ///   * and `SPOT_DEBUG_LOCATION` isn't set.
    ///
    /// Resolution order:
    ///   1. `SPOT_DEBUG_LOCATION="lat,lon"` env var (preferred, per-run)
    ///   2. Hardcoded developer fallback (`Self.debugSimulatorFallback`)
    ///
    /// No-op in release builds and on physical devices. Real
    /// CoreLocation fixes (including those from the GPX) override the
    /// synthetic value when they arrive via `didUpdateLocations`.
    private func applySimulatorOverrideIfNeeded() {
        #if targetEnvironment(simulator) && DEBUG
        guard userLocation == nil else { return }

        let coord: CLLocationCoordinate2D
        let source: String
        if let raw = ProcessInfo.processInfo.environment["SPOT_DEBUG_LOCATION"],
           let parsed = Self.parseEnvCoordinate(raw) {
            coord = parsed
            source = "env"
        } else {
            coord = Self.debugSimulatorFallback
            source = "hardcoded"
        }

        let synthetic = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        // Note: don't `cache(synthetic)` — the persisted last-known-good
        // is reserved for *real* CoreLocation fixes so the synthetic
        // override never leaks to a physical device through any shared
        // UserDefaults pathway.
        userLocation = synthetic
        SpotLogger.log(LocationManagerLogs.simulatorOverrideApplied, details: [
            "lat": coord.latitude,
            "lon": coord.longitude,
            "source": source
        ])
        #endif
    }

    /// Hardcoded coordinates used as the very last-resort fallback in
    /// DEBUG simulator builds. Edit here to change the default dev
    /// location (NJ near NYC by default).
    private static let debugSimulatorFallback = CLLocationCoordinate2D(
        latitude: 40.867449,
        longitude: -74.025070
    )

    /// Parse `"lat,lon"` strings like `"40.867449,-74.025070"`. Returns
    /// nil on any malformed input.
    private static func parseEnvCoordinate(_ raw: String) -> CLLocationCoordinate2D? {
        let parts = raw.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        let lat = parts[0]
        let lon = parts[1]
        guard CLLocationCoordinate2DIsValid(.init(latitude: lat, longitude: lon)) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Human-readable auth status for logs.
    fileprivate static func label(for status: CLAuthorizationStatus) -> String {
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

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
        Self.cache(location)
        SpotLogger.log(LocationManagerLogs.locationFixReceived, details: [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy
        ])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        SpotLogger.log(LocationManagerLogs.locationUpdateFailed, details: ["error": error.localizedDescription])
    }

    /// iOS 14+ uses the parameter-less `locationManagerDidChangeAuthorization`.
    /// We implement both because the deprecated form is still called on some
    /// system paths and because it's free defensive coverage.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.handleAuthorization(status: status)
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.handleAuthorization(status: status)
        }
    }

    private func handleAuthorization(status: CLAuthorizationStatus) {
        let changed = status != authorizationStatus
        authorizationStatus = status
        if changed {
            SpotLogger.log(LocationManagerLogs.authorizationChanged, details: [
                "status": Self.label(for: status)
            ])
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
            if pendingOneShotLocationRequest {
                pendingOneShotLocationRequest = false
                manager.requestLocation()
            }
        default:
            break
        }
    }
}
