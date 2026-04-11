import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    private let manager = CLLocationManager()

    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // Miami Beach coordinates as default
    static let defaultLocation = CLLocation(
        latitude: 25.7907,
        longitude: -80.1300
    )

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // Update location when user moves 10 meters
    }

    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
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
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        SpotLogger.log(LocationManagerLogs.locationUpdateFailed, details: ["error": error.localizedDescription])
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            default:
                break
            }
        }
    }
}
