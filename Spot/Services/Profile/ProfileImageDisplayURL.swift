//
//  ProfileImageDisplayURL.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Supabase

/// Turns a stored profile photo reference into a URL `AsyncImage` can load.
/// Legacy `https` values pass through. Moderated private objects are signed.
enum ProfileImageDisplayURL {
    private static let signedURLExpirySeconds = 604_800
    private static let cacheFreshnessSeconds: TimeInterval = 6 * 24 * 60 * 60

    static func resolve(_ raw: String?) async -> String? {
        let resolved = await resolveMany([raw])
        return lookup(raw, in: resolved)
    }

    static func lookup(_ raw: String?, in resolved: [String: String]) -> String? {
        guard let key = normalizedKey(raw) else { return nil }
        return resolved[key]
    }

    /// Keys are the trimmed stored strings. Failed signs are omitted so callers
    /// do not fall back to a `spot-storage://` value `AsyncImage` cannot load.
    static func resolveMany(_ raws: [String?]) async -> [String: String] {
        var output: [String: String] = [:]
        var pendingByBucket: [String: [String]] = [:]
        var rawKeysByObject: [String: [String]] = [:]

        for raw in raws {
            guard let key = normalizedKey(raw) else { continue }
            if output[key] != nil || rawKeysByObject[objectKey(forStored: key)] != nil { continue }
            switch ProfileImageReference.parse(key) {
            case .remote(let url):
                output[key] = url
            case .storage(let bucket, let path):
                let objectKey = "\(bucket)\n\(path)"
                if let cached = await ProfileImageSignedURLCache.shared.url(for: objectKey) {
                    output[key] = cached
                } else {
                    if pendingByBucket[bucket]?.contains(path) != true {
                        pendingByBucket[bucket, default: []].append(path)
                    }
                    rawKeysByObject[objectKey, default: []].append(key)
                }
            case nil:
                break
            }
        }

        for (bucket, paths) in pendingByBucket {
            do {
                let signed = try await supabase.storage
                    .from(bucket)
                    .createSignedURLs(paths: paths, expiresIn: signedURLExpirySeconds)
                for item in signed {
                    if case let .success(path, url) = item {
                        let objectKey = "\(bucket)\n\(path)"
                        let display = url.absoluteString
                        await ProfileImageSignedURLCache.shared.store(key: objectKey, url: display)
                        for rawKey in rawKeysByObject[objectKey] ?? [] {
                            output[rawKey] = display
                        }
                    }
                }
            } catch {
                SpotLogger.log(SupabaseUserServiceLogs.profileAvatarDisplaySignFailed, details: [
                    "bucket": bucket,
                    "count": paths.count,
                    "error": error.localizedDescription
                ])
            }
        }

        return output
    }

    private static func normalizedKey(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func objectKey(forStored key: String) -> String {
        switch ProfileImageReference.parse(key) {
        case .storage(let bucket, let path):
            return "\(bucket)\n\(path)"
        case .remote, nil:
            return "remote\n\(key)"
        }
    }
}

private actor ProfileImageSignedURLCache {
    static let shared = ProfileImageSignedURLCache()

    private var entries: [String: (url: String, freshUntil: Date)] = [:]

    func url(for key: String, now: Date = Date()) -> String? {
        guard let entry = entries[key], entry.freshUntil > now else { return nil }
        return entry.url
    }

    func store(key: String, url: String, now: Date = Date()) {
        entries[key] = (url, now.addingTimeInterval(ProfileImageDisplayURLCacheFreshness.seconds))
    }
}

enum ProfileImageDisplayURLCacheFreshness {
    static let seconds: TimeInterval = 6 * 24 * 60 * 60
}
