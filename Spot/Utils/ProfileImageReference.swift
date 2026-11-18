//
//  ProfileImageReference.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation

/// Stored profile photo value. Legacy rows are ordinary `https` URLs in the
/// public `avatars` bucket. Moderated photos are a private storage reference
/// (`spot-storage://approved_profile_images/<path>`) written only by
/// `set_profile_image_from_approved_asset_v1`.
enum ProfileImageReference: Equatable, Sendable {
    static let prefix = "spot-storage://"

    case remote(String)
    case storage(bucket: String, path: String)

    static func parse(_ raw: String?) -> ProfileImageReference? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix(prefix) else { return .remote(trimmed) }
        let rest = String(trimmed.dropFirst(prefix.count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let bucket = String(rest[..<slash])
        let path = String(rest[rest.index(after: slash)...])
        guard !bucket.isEmpty, !path.isEmpty, !bucket.contains("/") else { return nil }
        return .storage(bucket: bucket, path: path)
    }

    static func storageValue(bucket: String, path: String) -> String {
        "\(prefix)\(bucket)/\(path)"
    }
}

enum ProfileAvatarModerationCopy {
    static let rejected = "This photo can't be used as a profile picture. Please choose a different one."
    static let unavailable = "We couldn't check this photo. Please try again."

    /// `nil` when the image is approved. Otherwise the safe message to show.
    static func message(approved: Bool, reason: String?) -> String? {
        guard !approved else { return nil }
        if reason == "image_policy_rejected" { return rejected }
        return unavailable
    }
}
