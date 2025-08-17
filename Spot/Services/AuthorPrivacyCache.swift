import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Session-scoped, in-memory cache for author privacy and follow state.
/// Keyed by authorId.
/// Entry: `isPrivate`, `isFollowedByViewer`, `lastCheckedAt`.
actor AuthorPrivacyCache {
    struct Entry {
        var isPrivate: Bool
        var isFollowedByViewer: Bool
        var lastCheckedAt: Date
    }

    static let shared = AuthorPrivacyCache()
    private init() {}

    private let db = Firestore.firestore()
    private let ttl: TimeInterval = 60 * 5 // 5 minutes

    private var authorIdToEntry: [String: Entry] = [:]
    private var cachedFollowing: Set<String> = []
    private var followingFetchedAt: Date = .distantPast
    private var cachedBlockedUsers: Set<String> = []
    private var blockedFetchedAt: Date = .distantPast

    // MARK: Public API

    func clear() {
        authorIdToEntry.removeAll()
        cachedFollowing.removeAll()
        followingFetchedAt = .distantPast
        cachedBlockedUsers.removeAll()
        blockedFetchedAt = .distantPast
    }

    func invalidate(authorId: String) {
        authorIdToEntry.removeValue(forKey: authorId)
    }

    /// Preload cache for the provided authors in a single batched pass.
    /// Logs: Privacy.Cache warm authors=<n>
    @discardableResult
    func warm(authorIds: Set<String>) async {
        guard !authorIds.isEmpty else { return }

        // Refresh following + blocked once per TTL
        async let _ = refreshFollowingIfNeeded()
        async let __ = refreshBlockedIfNeeded()

        // Determine which authors are missing or stale
        let now = Date()
        var missing: [String] = []
        for id in authorIds {
            if let entry = authorIdToEntry[id], now.timeIntervalSince(entry.lastCheckedAt) < ttl {
                continue
            }
            missing.append(id)
        }

        guard !missing.isEmpty else { return }

        SpotLogger.info("Privacy.Cache warm authors=\(missing.count)")

        // Batch in chunks of up to 10 using documentId 'in' queries to avoid N+1
        let chunks: [[String]] = stride(from: 0, to: missing.count, by: 10).map {
            Array(missing[$0..<min($0 + 10, missing.count)])
        }

        let results = await withTaskGroup(of: [String: Entry].self, returning: [String: Entry].self) { group in
            for chunk in chunks {
                group.addTask { [db] in
                    var map: [String: Entry] = [:]
                    do {
                        let snap = try await db.collection("users").whereField(FieldPath.documentID(), in: chunk).getDocuments()
                        let now = Date()
                        for doc in snap.documents {
                            let uid = doc.documentID
                            let isPrivate = (doc.data()["isPrivate"] as? Bool) ?? false
                            map[uid] = Entry(isPrivate: isPrivate, isFollowedByViewer: false, lastCheckedAt: now)
                        }
                        // Mark non-returned as hidden
                        let returned = Set(snap.documents.map { $0.documentID })
                        let missingFromChunk = Set(chunk).subtracting(returned)
                        for uid in missingFromChunk {
                            map[uid] = Entry(isPrivate: true, isFollowedByViewer: false, lastCheckedAt: Date())
                        }
                    } catch {
                        SpotLogger.error("AuthorPrivacyCache warm failed for chunk count=\(chunk.count): \(error.localizedDescription)")
                    }
                    return map
                }
            }
            var combined: [String: Entry] = [:]
            for await part in group {
                for (k, v) in part { combined[k] = v }
            }
            return combined
        }
        // Now merge results into actor state, computing isFollowed based on current cachedFollowing
        let now2 = Date()
        for (uid, base) in results {
            let followed = cachedFollowing.contains(uid)
            authorIdToEntry[uid] = Entry(isPrivate: base.isPrivate, isFollowedByViewer: followed, lastCheckedAt: now2)
        }
    }

    /// Returns whether a spot authored by `authorId` should be visible to the current viewer.
    /// - Returns: true/false if known, or nil if cache-miss (will log and caller may decide to hide until warm()).
    func isAllowed(authorId: String) -> Bool? {
        guard let viewerId = Auth.auth().currentUser?.uid else { return true }
        if viewerId == authorId { return true }

        // Blocked users drop regardless of privacy
        if cachedBlockedUsers.contains(authorId) { return false }

        if let entry = authorIdToEntry[authorId], Date().timeIntervalSince(entry.lastCheckedAt) < ttl {
            if !entry.isPrivate { return true }
            return entry.isFollowedByViewer
        }

        SpotLogger.debug("Privacy.Cache miss authorId=\(authorId)")
        return nil
    }

    /// Apply privacy + blocked-user filter to spots. Will warm cache for unknown authors before evaluating.
    func filter(spots: [Spot]) async -> [Spot] {
        guard !spots.isEmpty else { return spots }
        let viewerId = Auth.auth().currentUser?.uid
        let authors = Set(spots.compactMap { $0.userId })
        await warm(authorIds: authors)

        var filtered: [Spot] = []
        for s in spots {
            guard let author = s.userId else { continue }
            if let v = viewerId, v == author { filtered.append(s); continue }
            if cachedBlockedUsers.contains(author) { 
                SpotLogger.info("Privacy.Drop spotId=\(s.id ?? "nil") authorId=\(author) reason=blocked_user")
                continue 
            }
            if let allowed = isAllowed(authorId: author) {
                if allowed { filtered.append(s) } else {
                    SpotLogger.info("Privacy.Drop spotId=\(s.id ?? "nil") authorId=\(author) reason=private_not_followed")
                }
            } else {
                // Unknown author after warm should be rare; default-hide
                SpotLogger.info("Privacy.Drop spotId=\(s.id ?? "nil") authorId=\(author) reason=unknown_author")
            }
        }
        return filtered
    }

    // MARK: Internals

    private func refreshFollowingIfNeeded() async {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        if Date().timeIntervalSince(followingFetchedAt) < ttl { return }
        do {
            let doc = try await db.collection("users").document(viewerId).getDocument()
            let arr = (doc.data()? ["following"] as? [String]) ?? []
            cachedFollowing = Set(arr)
            followingFetchedAt = Date()
        } catch {
            SpotLogger.error("AuthorPrivacyCache: failed to refresh following: \(error.localizedDescription)")
        }
    }

    private func refreshBlockedIfNeeded() async {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        if Date().timeIntervalSince(blockedFetchedAt) < ttl { return }
        do {
            let doc = try await db.collection("users").document(viewerId).getDocument()
            let arr = (doc.data()? ["blockedUsers"] as? [String]) ?? []
            cachedBlockedUsers = Set(arr)
            blockedFetchedAt = Date()
        } catch {
            SpotLogger.error("AuthorPrivacyCache: failed to refresh blocked users: \(error.localizedDescription)")
        }
    }
}



