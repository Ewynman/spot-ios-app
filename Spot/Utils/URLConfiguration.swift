//
//  URLConfiguration.swift
//  Spot
//
//  Created by Edward Wynman on 1/12/26.
//

import Foundation

struct URLConfiguration {
    static let shared = URLConfiguration()

    private let plist: [String: Any]

    #if DEBUG
    private static let debugOnlyUniversalLinkHosts: [String] = [
        "localhost",
        "454ab5d34eb4.ngrok-free.app"
    ]
    #endif
    #if RELEASE
    private static let releaseOnlyUniversalLinkHosts: [String] = [
        "spotapp.online",
        "www.spotapp.online",
        "454ab5d34eb4.ngrok-free.app"
    ]
    #else
    private static let releaseOnlyUniversalLinkHosts: [String] = []
    #endif

    private init() {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            fatalError("Could not load Info.plist")
        }
        self.plist = plist
    }

    // MARK: - Universal Link Domains

    /// Production hosts come from `Info.plist` → `SpotURLs` → `universalLinkDomains`.
    /// In Debug, `debugOnlyUniversalLinkHosts` are appended so localhost / tunnel testing works without shipping those in Release.
    var universalLinkDomains: [String] {
        guard let spotURLs = plist["SpotURLs"] as? [String: Any],
              let domains = spotURLs["universalLinkDomains"] as? [String] else {
            #if DEBUG
            return Self.debugOnlyUniversalLinkHosts
            #else
            return []
            #endif
        }
        #if DEBUG
        let merged = domains + Self.debugOnlyUniversalLinkHosts
        return Array(Set(merged)).sorted()
        #else
        return domains
        #endif
    }

    // MARK: - Share URL
    var shareURLBase: String {
        guard let spotURLs = plist["SpotURLs"] as? [String: Any],
              let base = spotURLs["shareURLBase"] as? String else {
            return ""
        }
        return base
    }

    func shareURL(for spotId: String) -> String {
        return "\(shareURLBase)/s/\(spotId)"
    }

    // MARK: - Custom Scheme
    var customScheme: String {
        guard let spotURLs = plist["SpotURLs"] as? [String: Any],
              let scheme = spotURLs["customScheme"] as? String else {
            return ""
        }
        return scheme
    }

    // MARK: - URL Validation
    func isAllowedUniversalLinkHost(_ host: String) -> Bool {
        return universalLinkDomains.contains(host)
    }
}
