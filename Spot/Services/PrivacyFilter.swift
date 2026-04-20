//
//  PrivacyFilter.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation
import FirebaseFirestore

class PrivacyFilter {
    static let shared = PrivacyFilter()
    private init() {}

    private var followingCache: Set<String> = []
    private var privateUsersCache: [String: Bool] = [:]
    private var cacheTimestamp: Date = Date.distantPast
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    /// Filter spots to exclude private users' content from non-followers
    func filterSpotsForPrivacy(_ spots: [Spot]) async -> [Spot] {
        // Deprecated: use AuthorPrivacyCache instead to ensure single-batch fetch and shared TTL
        return await AuthorPrivacyCache.shared.filter(spots: spots)
    }

    /// Check if a specific user's content should be visible to current user
    func shouldShowContent(from authorId: String) async -> Bool {
        guard let currentUserId = SpotAuthBridge.currentUserId else {
            return false
        }

        // Always show own content
        if authorId == currentUserId { return true }

        // Check if author is private
        let isPrivate = await fetchPrivateStatus(for: [authorId])[authorId] ?? false

        if isPrivate {
            // Only show if current user is following
            let following = await fetchFollowingList(for: currentUserId)
            return following.contains(authorId)
        }

        return true
    }

    // MARK: - Private Methods

    private func fetchFollowingList(for userId: String) async -> Set<String> {
        // Check cache first
        if Date().timeIntervalSince(cacheTimestamp) < cacheValidityDuration && !followingCache.isEmpty {
            return followingCache
        }

        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .getDocument()

            let following = doc.data()? ["following"] as? [String] ?? []
            followingCache = Set(following)
            cacheTimestamp = Date()

            return followingCache
        } catch {
            SpotLogger.log(PrivacyFilterLogs.fetchFollowingListFailed, details: ["error": error.localizedDescription])
            return []
        }
    }

    private func fetchPrivateStatus(for userIds: Set<String>) async -> [String: Bool] {
        // Check cache for known users
        var result: [String: Bool] = [:]
        let uncachedIds = userIds.filter { privateUsersCache[$0] == nil }

        // Add cached results
        for userId in userIds {
            if let cached = privateUsersCache[userId] {
                result[userId] = cached
            }
        }

        // Fetch uncached users
        if !uncachedIds.isEmpty {
            do {
                let documents = try await withThrowingTaskGroup(of: (String, DocumentSnapshot).self) { group in
                    for userId in uncachedIds {
                        group.addTask {
                            let doc = try await Firestore.firestore()
                                .collection("users")
                                .document(userId)
                                .getDocument()
                            return (userId, doc)
                        }
                    }
                    var results: [(String, DocumentSnapshot)] = []
                    for try await item in group { results.append(item) }
                    return results
                }

                for (userId, doc) in documents {
                    let isPrivate = doc.data()? ["isPrivate"] as? Bool ?? false
                    result[userId] = isPrivate
                    privateUsersCache[userId] = isPrivate
                }
            } catch {
                SpotLogger.log(PrivacyFilterLogs.fetchPrivateStatusFailed, details: ["error": error.localizedDescription])
            }
        }

        return result
    }

    /// Clear cache (useful for testing or when user follows/unfollows)
    func clearCache() {
        followingCache.removeAll()
        privateUsersCache.removeAll()
        cacheTimestamp = Date.distantPast
    }
}
