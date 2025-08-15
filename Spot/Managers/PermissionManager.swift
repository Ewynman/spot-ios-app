//
//  PermissionManager.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import CoreLocation
import UserNotifications
import UIKit

class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()
    private let locationManager = CLLocationManager()
    
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var showLocationBanner = false
    @Published var showNotificationBanner = false
    
    private override init() {
        super.init()
        locationManager.delegate = self
        updatePermissionStatuses()
    }
    
    // MARK: - Permission Status Updates
    
    func updatePermissionStatuses() {
        locationStatus = locationManager.authorizationStatus
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }
    
    // MARK: - Post-Login Permission Requests
    
    /// Request permissions after successful login if not determined
    func requestPermissionsIfNeeded() {
        requestLocationPermissionIfNeeded()
        requestNotificationPermissionIfNeeded()
    }
    
    private func requestLocationPermissionIfNeeded() {
        let userDefaults = UserDefaults.standard
        let hasRequested = userDefaults.bool(forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        
        if !hasRequested && locationStatus == .notDetermined {
            SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=location result=requesting")
            locationManager.requestWhenInUseAuthorization()
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        }
    }
    
    private func requestNotificationPermissionIfNeeded() {
        let userDefaults = UserDefaults.standard
        let hasRequested = userDefaults.bool(forKey: Constants.UserDefaultsKeys.notificationsRequested)
        
        if !hasRequested && notificationStatus == .notDetermined {
            SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=push result=requesting")
            
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=push result=granted")
                    } else {
                        SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=push result=denied")
                        self.showNotificationBanner = true
                    }
                    self.updatePermissionStatuses()
                }
            }
            
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.notificationsRequested)
        }
    }
    
    // MARK: - Banner Actions
    
    func openLocationSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    func openNotificationSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    func dismissLocationBanner() {
        showLocationBanner = false
    }
    
    func dismissNotificationBanner() {
        showNotificationBanner = false
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        locationStatus = newStatus
        
        switch newStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=location result=granted")
            showLocationBanner = false
        case .denied, .restricted:
            SpotLogger.info("\(Constants.Analytics.permissionsRequested) type=location result=denied")
            showLocationBanner = true
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
