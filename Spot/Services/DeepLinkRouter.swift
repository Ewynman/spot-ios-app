//
//  DeepLinkRouter.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation
import UIKit

enum DeepLinkRoute {
    case spotDetail(spotId: String)
    case unknown
}

enum DeepLinkOrigin {
    case universalLink
    case customScheme
}

struct DeepLinkAnalytics {
    let origin: DeepLinkOrigin
    let spotId: String?
    let appVersion: String
    let isColdStart: Bool
    let success: Bool
    let errorReason: String?
}

final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private init() {}
    
    // MARK: - URL Parsing
    
    func parseURL(_ url: URL) -> DeepLinkRoute {
        SpotLogger.debug("DeepLinkRouter: Parsing URL: \(url.absoluteString)")
        
        // Handle Universal Links (https://spotapp.online/s/:spotId)
        if url.scheme == "https" && (url.host == "spotapp.online" || url.host == "www.spotapp.online") {
            return parseUniversalLink(url)
        }
        
        // Handle Custom Scheme (spotapp://spot/:spotId)
        if url.scheme == "spotapp" {
            return parseCustomScheme(url)
        }
        
        SpotLogger.warning("DeepLinkRouter: Unknown URL scheme: \(url.scheme ?? "nil")")
        return .unknown
    }
    
    private func parseUniversalLink(_ url: URL) -> DeepLinkRoute {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Pattern: /s/:spotId
        if pathComponents.count == 2 && pathComponents[0] == "s" {
            let spotId = pathComponents[1]
            if isValidSpotId(spotId) {
                SpotLogger.info("DeepLinkRouter: Parsed Universal Link for spot: \(spotId)")
                return .spotDetail(spotId: spotId)
            } else {
                SpotLogger.warning("DeepLinkRouter: Invalid spot ID in Universal Link: \(spotId)")
            }
        }
        
        SpotLogger.warning("DeepLinkRouter: Invalid Universal Link path: \(url.path)")
        return .unknown
    }
    
    private func parseCustomScheme(_ url: URL) -> DeepLinkRoute {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Pattern: spot/:spotId
        if pathComponents.count == 2 && pathComponents[0] == "spot" {
            let spotId = pathComponents[1]
            if isValidSpotId(spotId) {
                SpotLogger.info("DeepLinkRouter: Parsed Custom Scheme for spot: \(spotId)")
                return .spotDetail(spotId: spotId)
            } else {
                SpotLogger.warning("DeepLinkRouter: Invalid spot ID in Custom Scheme: \(spotId)")
            }
        }
        
        SpotLogger.warning("DeepLinkRouter: Invalid Custom Scheme path: \(url.path)")
        return .unknown
    }
    
    private func isValidSpotId(_ spotId: String) -> Bool {
        // Basic validation: non-empty and reasonable length
        return !spotId.isEmpty && spotId.count <= 50 && spotId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil
    }
    
    // MARK: - Analytics
    
    func logDeepLinkEvent(origin: DeepLinkOrigin, spotId: String?, isColdStart: Bool, success: Bool, errorReason: String? = nil) {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        let analytics = DeepLinkAnalytics(
            origin: origin,
            spotId: spotId,
            appVersion: appVersion,
            isColdStart: isColdStart,
            success: success,
            errorReason: errorReason
        )
        
        if success {
            SpotLogger.info("DeepLinkRouter: Success - origin: \(origin), spotId: \(spotId ?? "nil"), coldStart: \(isColdStart)")
        } else {
            SpotLogger.error("DeepLinkRouter: Failure - origin: \(origin), spotId: \(spotId ?? "nil"), reason: \(errorReason ?? "unknown")")
        }
        
        // TODO: Send to analytics service when implemented
        // AnalyticsService.shared.trackDeepLink(analytics)
    }
}
