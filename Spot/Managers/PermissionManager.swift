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

@MainActor
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

    // MARK: - Explicit Requests (for onboarding buttons)
    func requestLocationPermission() {
        updatePermissionStatuses()
        if locationStatus == .notDetermined {
            SpotLogger.log(PermissionManagerLogs.locationPermissionRequestedExplicit)
            Task { @MainActor in
                AnalyticsService.shared.trackPermissionRequest(type: "location", action: "explicit")
            }
            locationManager.requestWhenInUseAuthorization()
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        } else if locationStatus == .denied || locationStatus == .restricted {
            showLocationBanner = true
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                self.notificationStatus = status
                switch status {
                case .notDetermined:
                    SpotLogger.log(PermissionManagerLogs.pushPermissionRequestedExplicit)
                    Task { @MainActor in
                        AnalyticsService.shared.trackPermissionRequest(type: "push", action: "explicit")
                    }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted {
                                SpotLogger.log(PermissionManagerLogs.pushPermissionGranted)
                                Task { @MainActor in
                                    AnalyticsService.shared.trackPermissionRequest(type: "push", action: "explicit", result: "granted")
                                }
                            } else {
                                SpotLogger.log(PermissionManagerLogs.pushPermissionDenied)
                                Task { @MainActor in
                                    AnalyticsService.shared.trackPermissionRequest(type: "push", action: "explicit", result: "denied")
                                }
                                self.showNotificationBanner = true
                            }
                            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.notificationsRequested)
                            self.updatePermissionStatuses()
                        }
                    }
                case .denied, .provisional, .ephemeral:
                    self.showNotificationBanner = true
                case .authorized:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func requestLocationPermissionIfNeeded() {
        let userDefaults = UserDefaults.standard
        let hasRequested = userDefaults.bool(forKey: Constants.UserDefaultsKeys.locationPermissionRequested)

        if !hasRequested && locationStatus == .notDetermined {
        SpotLogger.log(PermissionManagerLogs.locationPermissionRequesting)
            Task { @MainActor in
                AnalyticsService.shared.trackPermissionRequest(type: "location", action: "auto")
            }
            locationManager.requestWhenInUseAuthorization()
            userDefaults.set(true, forKey: Constants.UserDefaultsKeys.locationPermissionRequested)
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        let userDefaults = UserDefaults.standard
        let hasRequested = userDefaults.bool(forKey: Constants.UserDefaultsKeys.notificationsRequested)

        if !hasRequested && notificationStatus == .notDetermined {
            SpotLogger.log(PermissionManagerLogs.pushPermissionRequesting)
            Task { @MainActor in
                AnalyticsService.shared.trackPermissionRequest(type: "push", action: "auto")
            }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        SpotLogger.log(PermissionManagerLogs.pushPermissionGranted)
                        Task { @MainActor in
                            AnalyticsService.shared.trackPermissionRequest(type: "push", action: "auto", result: "granted")
                        }
                    } else {
                        SpotLogger.log(PermissionManagerLogs.pushPermissionDenied)
                        Task { @MainActor in
                            AnalyticsService.shared.trackPermissionRequest(type: "push", action: "auto", result: "denied")
                        }
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
            SpotLogger.log(PermissionManagerLogs.locationPermissionGranted)
            Task { @MainActor in
                AnalyticsService.shared.trackPermissionRequest(type: "location", action: "system_change", result: "granted")
            }
            showLocationBanner = false
        case .denied, .restricted:
            SpotLogger.log(PermissionManagerLogs.locationPermissionDenied)
            Task { @MainActor in
                AnalyticsService.shared.trackPermissionRequest(type: "location", action: "system_change", result: "denied")
            }
            showLocationBanner = true
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
