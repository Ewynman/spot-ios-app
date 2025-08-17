//
//  DeepLinkState.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import SwiftUI
import Foundation
import FirebaseAuth

@MainActor
final class DeepLinkState: ObservableObject {
    static let shared = DeepLinkState()
    private init() {}
    
    @Published var pendingDeepLink: DeepLinkRoute?
    @Published var isNavigatingToSpot = false
    @Published var spotDetailSpot: Spot?
    @Published var showSpotUnavailable = false
    @Published var isLoadingSpot = false
    
    private let router = DeepLinkRouter.shared
    private let spotService = SpotService.shared
    
    // Idempotency and debouncing
    private var lastProcessedSpotId: String?
    private var lastProcessedTimestamp: Date = Date.distantPast
    private let debounceInterval: TimeInterval = 1.0 // 1 second debounce
    
    // MARK: - Deep Link Handling
    
    func handleDeepLink(_ url: URL, origin: DeepLinkOrigin, isColdStart: Bool = false) {
        SpotLogger.info("DeepLinkState: Handling deep link - \(url.absoluteString), origin: \(origin), coldStart: \(isColdStart)")
        
        let route = router.parseURL(url)
        
        switch route {
        case .spotDetail(let spotId):
            handleSpotDetailDeepLink(spotId: spotId, origin: origin, isColdStart: isColdStart)
        case .unknown:
            router.logDeepLinkEvent(
                origin: origin,
                spotId: nil,
                isColdStart: isColdStart,
                success: false,
                errorReason: "Unknown route"
            )
        }
    }
    
    func handleInitialUserActivity(_ userActivity: NSUserActivity) {
        // Handle Universal Links that launched the app (cold start)
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        
        SpotLogger.info("DeepLinkState: Handling initial user activity - \(url.absoluteString)")
        handleDeepLink(url, origin: .universalLink, isColdStart: true)
    }
    
    private func handleSpotDetailDeepLink(spotId: String, origin: DeepLinkOrigin, isColdStart: Bool) {
        // Check for idempotency - if we're already showing this spot, do nothing
        if let currentSpotId = lastProcessedSpotId, currentSpotId == spotId {
            let timeSinceLastProcess = Date().timeIntervalSince(lastProcessedTimestamp)
            if timeSinceLastProcess < debounceInterval {
                SpotLogger.info("DeepLinkState: Ignoring duplicate deep link for spot: \(spotId) (debounced)")
                return
            }
        }
        
        // Update tracking
        lastProcessedSpotId = spotId
        lastProcessedTimestamp = Date()
        
        // If app is still starting up, store the pending deep link
        if isColdStart {
            pendingDeepLink = .spotDetail(spotId: spotId)
            SpotLogger.info("DeepLinkState: Stored pending deep link for spot: \(spotId)")
            return
        }
        
        // Check if user is authenticated before navigating
        if Auth.auth().currentUser != nil {
            // Navigate immediately for warm start
            navigateToSpot(spotId: spotId, origin: origin, isColdStart: isColdStart)
        } else {
            // Store for later when user authenticates
            pendingDeepLink = .spotDetail(spotId: spotId)
            SpotLogger.info("DeepLinkState: Stored pending deep link for unauthenticated user: \(spotId)")
        }
    }
    
    func processPendingDeepLinks() {
        guard let pending = pendingDeepLink else { return }
        
        SpotLogger.info("DeepLinkState: Processing pending deep link")
        
        switch pending {
        case .spotDetail(let spotId):
            navigateToSpot(spotId: spotId, origin: .universalLink, isColdStart: true)
        case .unknown:
            break
        }
        
        pendingDeepLink = nil
    }
    
    private func navigateToSpot(spotId: String, origin: DeepLinkOrigin, isColdStart: Bool) {
        Task {
            await fetchAndNavigateToSpot(spotId: spotId, origin: origin, isColdStart: isColdStart)
        }
    }
    
    private func fetchAndNavigateToSpot(spotId: String, origin: DeepLinkOrigin, isColdStart: Bool) async {
        await MainActor.run {
            isLoadingSpot = true
        }
        
        do {
            guard let spot = try await spotService.fetchSpotById(spotId) else {
                // Spot not found or blocked
                let result = "not_found"
                SpotLogger.info("DeepLinkState: Deep link result - origin: \(origin), spotId: \(spotId), startup: \(isColdStart ? "cold" : "warm"), result: \(result)")
                
                router.logDeepLinkEvent(
                    origin: origin,
                    spotId: spotId,
                    isColdStart: isColdStart,
                    success: false,
                    errorReason: "Spot not found or blocked"
                )
                
                await MainActor.run {
                    isLoadingSpot = false
                    showSpotUnavailable = true
                }
                return
            }
            
            // Success - navigate to spot
            let result = "navigated"
            SpotLogger.info("DeepLinkState: Deep link result - origin: \(origin), spotId: \(spotId), startup: \(isColdStart ? "cold" : "warm"), result: \(result)")
            
            router.logDeepLinkEvent(
                origin: origin,
                spotId: spotId,
                isColdStart: isColdStart,
                success: true
            )
            
            await MainActor.run {
                spotDetailSpot = spot
                isLoadingSpot = false
                isNavigatingToSpot = true
            }
            
        } catch {
            SpotLogger.error("DeepLinkState: Failed to fetch spot: \(error.localizedDescription)")
            
            let result = "error:\(error.localizedDescription)"
            SpotLogger.info("DeepLinkState: Deep link result - origin: \(origin), spotId: \(spotId), startup: \(isColdStart ? "cold" : "warm"), result: \(result)")
            
            router.logDeepLinkEvent(
                origin: origin,
                spotId: spotId,
                isColdStart: isColdStart,
                success: false,
                errorReason: error.localizedDescription
            )
            
            await MainActor.run {
                isLoadingSpot = false
                showSpotUnavailable = true
            }
        }
    }
    
    // MARK: - Public Navigation
    
    func openSpot(_ spotId: String) {
        navigateToSpot(spotId: spotId, origin: .customScheme, isColdStart: false)
    }
    
    func dismissSpotDetail() {
        spotDetailSpot = nil
        isNavigatingToSpot = false
        showSpotUnavailable = false
        isLoadingSpot = false
    }
    
    func dismissSpotUnavailable() {
        showSpotUnavailable = false
    }
    
    // MARK: - User Session Management
    
    func clearUserSession() {
        // Clear all state when user logs out
        pendingDeepLink = nil
        isNavigatingToSpot = false
        spotDetailSpot = nil
        showSpotUnavailable = false
        isLoadingSpot = false
        lastProcessedSpotId = nil
        lastProcessedTimestamp = Date.distantPast
        
        SpotLogger.info("DeepLinkState: Cleared user session state")
    }
}
