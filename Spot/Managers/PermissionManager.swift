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
import Photos
import AVFoundation

@MainActor
class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()
    private let locationManager = CLLocationManager()

    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var photoStatus: PHAuthorizationStatus = .notDetermined
    @Published var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published var showLocationBanner = false
    @Published var showNotificationBanner = false
    @Published private(set) var lifecycleRefreshTick: Int = 0
    private var activeObserver: NSObjectProtocol?

    private override init() {
        super.init()
        locationManager.delegate = self
        startWatchingAppLifecycle()
        updatePermissionStatuses()
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    // MARK: - Permission Status Updates

    func updatePermissionStatuses() {
        locationStatus = locationManager.authorizationStatus
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    private func startWatchingAppLifecycle() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePermissionStatuses()
                self.lifecycleRefreshTick += 1
            }
        }
    }

    // MARK: - Post-Login Permission Requests

    /// Request permissions after successful login if not determined
    func requestPermissionsIfNeeded() {
        requestLocationPermissionIfNeeded()
        requestNotificationPermissionIfNeeded()
        requestPhotoPermissionIfNeeded()
        requestCameraPermissionIfNeeded()
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

    func requestPhotoPermission() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoStatus = currentStatus
        guard currentStatus == .notDetermined else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
            DispatchQueue.main.async {
                self.photoStatus = newStatus
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.photoPermissionRequested)
            }
        }
    }

    func requestCameraPermission() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraStatus = currentStatus
        guard currentStatus == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.cameraPermissionRequested)
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

    private func requestPhotoPermissionIfNeeded() {
        let hasRequested = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.photoPermissionRequested)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoStatus = status
        if !hasRequested && status == .notDetermined {
            requestPhotoPermission()
        }
    }

    private func requestCameraPermissionIfNeeded() {
        let hasRequested = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.cameraPermissionRequested)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraStatus = status
        if !hasRequested && status == .notDetermined {
            requestCameraPermission()
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

    func openPhotoSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }

    func openCameraSettings() {
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

    /// Core Location calls the delegate off the main actor; keep updates on `@MainActor` here.
    private func applyLocationAuthorizationChange(_ newStatus: CLAuthorizationStatus) {
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

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.applyLocationAuthorizationChange(newStatus)
        }
    }
}
