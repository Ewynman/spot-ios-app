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
    
    private func handleSpotDetailDeepLink(spotId: String, origin: DeepLinkOrigin, isColdStart: Bool) {
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
    
    // MARK: - Testing
    
    func testDeepLink() {
        // Test with a sample spot ID - replace with a real one from your database
        let testSpotId = "test_spot_id"
        SpotLogger.info("DeepLinkState: Testing deep link with spot ID: \(testSpotId)")
        openSpot(testSpotId)
    }
    
    func testWithRealSpot() {
        // This method can be used to test with a real spot from the database
        // You can replace this with actual spot fetching logic
        Task {
            do {
                // Get the first spot from the feed for testing
                let spots = try await SpotService.shared.fetchSpotsForMap(forceRefresh: true) { result in
                    switch result {
                    case .success(let spots):
                        if let firstSpot = spots.first, let spotId = firstSpot.id {
                            DispatchQueue.main.async {
                                self.openSpot(spotId)
                            }
                        }
                    case .failure(let error):
                        SpotLogger.error("Failed to get test spot: \(error.localizedDescription)")
                    }
                }
            } catch {
                SpotLogger.error("Failed to test with real spot: \(error.localizedDescription)")
            }
        }
    }
}
