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
        SpotLogger.debug("DeepLinkRouter: Host: \(url.host ?? "nil"), Path: \(url.path), PathComponents: \(url.pathComponents)")

        // Handle Universal Links (https://spotapp.online/s/:spotId, localhost for testing, or ngrok for DEBUG)
        if url.scheme == "https" && (url.host == "spotapp.online" || url.host == "www.spotapp.online" || url.host == "localhost" || url.host == "454ab5d34eb4.ngrok-free.app") {
            return parseUniversalLink(url)
        }

        // Handle HTTP localhost for testing
        if url.scheme == "http" && url.host == "localhost" {
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
        let host = url.host?.lowercased()

        SpotLogger.debug("DeepLinkRouter: Custom scheme parsing - Host: \(host ?? "nil"), PathComponents: \(pathComponents)")

        // Pattern 1: spotapp://spot/:spotId (host = "spot", path = "/:spotId")
        if host == "spot" && pathComponents.count == 1 {
            let spotId = pathComponents[0]
            if isValidSpotId(spotId) {
                SpotLogger.info("DeepLinkRouter: Parsed Custom Scheme (host variant) for spot: \(spotId)")
                return .spotDetail(spotId: spotId)
            } else {
                SpotLogger.warning("DeepLinkRouter: Invalid spot ID in Custom Scheme (host variant): \(spotId)")
            }
        }

        // Pattern 2: spotapp:///spot/:spotId (host = nil, path = "/spot/:spotId")
        if host == nil && pathComponents.count == 2 && pathComponents[0].lowercased() == "spot" {
            let spotId = pathComponents[1]
            if isValidSpotId(spotId) {
                SpotLogger.info("DeepLinkRouter: Parsed Custom Scheme (path variant) for spot: \(spotId)")
                return .spotDetail(spotId: spotId)
            } else {
                SpotLogger.warning("DeepLinkRouter: Invalid spot ID in Custom Scheme (path variant): \(spotId)")
            }
        }

        // Pattern 3: spotapp://open?spotId=:spotId (query variant)
        if host == "open" || (host == nil && pathComponents.count == 1 && pathComponents[0].lowercased() == "open") {
            if let spotId = url.queryParameters?["spotId"] {
                if isValidSpotId(spotId) {
                    SpotLogger.info("DeepLinkRouter: Parsed Custom Scheme (query variant) for spot: \(spotId)")
                    return .spotDetail(spotId: spotId)
                } else {
                    SpotLogger.warning("DeepLinkRouter: Invalid spot ID in Custom Scheme (query variant): \(spotId)")
                }
            }
        }

        SpotLogger.warning("DeepLinkRouter: Invalid Custom Scheme - Host: \(host ?? "nil"), Path: \(url.path)")
        return .unknown
    }

    private func isValidSpotId(_ spotId: String) -> Bool {
        // Basic validation: non-empty and reasonable length
        return !spotId.isEmpty && spotId.count <= 50 && spotId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil
    }
}

// MARK: - URL Extensions

extension URL {
    var queryParameters: [String: String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else { return nil }

        var items: [String: String] = [:]
        for queryItem in queryItems {
            items[queryItem.name] = queryItem.value
        }
        return items
    }
}

// MARK: - Analytics

extension DeepLinkRouter {
    func logDeepLinkEvent(origin: DeepLinkOrigin, spotId: String?, isColdStart: Bool, success: Bool, errorReason: String? = nil) {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        _ = DeepLinkAnalytics(
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
