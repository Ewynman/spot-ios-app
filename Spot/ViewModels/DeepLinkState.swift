//
//  DeepLinkState.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import SwiftUI
import Foundation
import FirebaseFirestore

@MainActor
final class DeepLinkState: ObservableObject {
    static let shared = DeepLinkState()
    private init() {}

    @Published var pendingDeepLink: DeepLinkRoute?
    @Published var isNavigatingToSpot = false
    @Published var spotDetailSpot: Spot?
    @Published var showSpotUnavailable = false
    @Published var isLoadingSpot = false
    @Published var showSubscriptionSuccess = false

    private let router = DeepLinkRouter.shared
    private let spotService = SpotService.shared

    // Idempotency and debouncing
    private var lastProcessedSpotId: String?
    private var lastProcessedTimestamp: Date = Date.distantPast
    private let debounceInterval: TimeInterval = 1.0 // 1 second debounce

    // MARK: - Deep Link Handling

    func handleDeepLink(_ url: URL, origin: DeepLinkOrigin, isColdStart: Bool = false) {
        SpotLogger.log(DeepLinkStateLogs.handlingDeepLink, details: ["url": url.absoluteString, "origin": "\(origin)", "coldStart": isColdStart])

        let route = router.parseURL(url)

        switch route {
        case .spotDetail(let spotId):
            handleSpotDetailDeepLink(spotId: spotId, origin: origin, isColdStart: isColdStart)
        case .subscriptionReturn:
            handleSubscriptionReturn(origin: origin, isColdStart: isColdStart)
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

        SpotLogger.log(DeepLinkStateLogs.handlingInitialUserActivity, details: ["url": url.absoluteString])
        handleDeepLink(url, origin: .universalLink, isColdStart: true)
    }

    private func handleSpotDetailDeepLink(spotId: String, origin: DeepLinkOrigin, isColdStart: Bool) {
        // Check for idempotency - if we're already showing this spot, do nothing
        if let currentSpotId = lastProcessedSpotId, currentSpotId == spotId {
            let timeSinceLastProcess = Date().timeIntervalSince(lastProcessedTimestamp)
            if timeSinceLastProcess < debounceInterval {
                SpotLogger.log(DeepLinkStateLogs.ignoringDuplicateDeepLink, details: ["spotId": spotId])
                return
            }
        }

        // Update tracking
        lastProcessedSpotId = spotId
        lastProcessedTimestamp = Date()

        // If app is still starting up, store the pending deep link
        if isColdStart {
            pendingDeepLink = .spotDetail(spotId: spotId)
            SpotLogger.log(DeepLinkStateLogs.storedPendingDeepLink, details: ["spotId": spotId])
            return
        }

        // Check if user is authenticated before navigating
        if SpotAuthBridge.currentUserId != nil {
            // Navigate immediately for warm start
            navigateToSpot(spotId: spotId, origin: origin, isColdStart: isColdStart)
        } else {
            // Store for later when user authenticates
            pendingDeepLink = .spotDetail(spotId: spotId)
            SpotLogger.log(DeepLinkStateLogs.storedPendingDeepLinkUnauthenticated, details: ["spotId": spotId])
        }
    }

    func processPendingDeepLinks() {
        guard let pending = pendingDeepLink else { return }

        SpotLogger.log(DeepLinkStateLogs.processingPendingDeepLink)

        switch pending {
        case .spotDetail(let spotId):
            navigateToSpot(spotId: spotId, origin: .universalLink, isColdStart: true)
        case .subscriptionReturn:
            handleSubscriptionReturn(origin: .universalLink, isColdStart: true)
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
                SpotLogger.log(DeepLinkStateLogs.deepLinkResult, details: ["origin": "\(origin)", "spotId": spotId, "startup": isColdStart ? "cold" : "warm", "result": "\(result)"])

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
            SpotLogger.log(DeepLinkStateLogs.deepLinkResult, details: ["origin": "\(origin)", "spotId": spotId, "startup": isColdStart ? "cold" : "warm", "result": "\(result)"])

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
            SpotLogger.log(DeepLinkStateLogs.fetchSpotFailed, details: ["error": error.localizedDescription])

            let result = "error:\(error.localizedDescription)"
            SpotLogger.log(DeepLinkStateLogs.deepLinkResult, details: ["origin": "\(origin)", "spotId": spotId, "startup": isColdStart ? "cold" : "warm", "result": "\(result)"])

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
        showSubscriptionSuccess = false
        lastProcessedSpotId = nil
        lastProcessedTimestamp = Date.distantPast

        SpotLogger.log(DeepLinkStateLogs.clearedUserSessionState)
    }
    
    // MARK: - Subscription Return Handling
    
    private func handleSubscriptionReturn(origin: DeepLinkOrigin, isColdStart: Bool) {
        SpotLogger.log(DeepLinkStateLogs.handlingSubscriptionReturn, details: ["origin": "\(origin)", "coldStart": isColdStart])
        
        // If app is still starting up, store the pending deep link
        if isColdStart {
            pendingDeepLink = .subscriptionReturn
            SpotLogger.log(DeepLinkStateLogs.storedPendingSubscriptionReturn)
            return
        }
        
        // Check if user is authenticated before checking pro status
        if SpotAuthBridge.currentUserId != nil {
            checkProStatusAndShowSuccess()
        } else {
            // Store for later when user authenticates
            pendingDeepLink = .subscriptionReturn
            SpotLogger.log(DeepLinkStateLogs.storedPendingSubscriptionReturnUnauthenticated)
        }
    }
    
    private func checkProStatusAndShowSuccess() {
        Task {
            guard let userId = SpotAuthBridge.currentUserId else {
                SpotLogger.log(DeepLinkStateLogs.noUserIdForSubscriptionCheck)
                return
            }
            
            do {
                let userDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .getDocument()
                
                let isPro = userDoc.data()?["isPro"] as? Bool ?? false
                
                await MainActor.run {
                    if isPro {
                        SpotLogger.log(DeepLinkStateLogs.userIsProShowingSuccess)
                        showSubscriptionSuccess = true
                    } else {
                        SpotLogger.log(DeepLinkStateLogs.userIsNotProDismissing)
                        // User didn't complete subscription, just close
                    }
                }
            } catch {
                SpotLogger.log(DeepLinkStateLogs.checkProStatusFailed, details: ["error": error.localizedDescription])
            }
        }
    }
    
    func dismissSubscriptionSuccess() {
        showSubscriptionSuccess = false
    }
}
