//
//  PermissionManager.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import CoreLocation
import UserNotifications

class PermissionManager: NSObject, ObservableObject {
    
    static let shared = PermissionManager()
    
    private let locationManager = CLLocationManager()

    override private init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Location Permission
    
    func requestLocationPermission() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // You can show an alert to guide user to Settings
            print("Location access denied.")
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location access granted.")
        @unknown default:
            break
        }
    }

    // MARK: - Notification Permission

    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location authorized")
        case .denied, .restricted:
            print("Location denied")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
