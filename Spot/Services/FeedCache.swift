import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FeedCache {
    static let shared = FeedCache()
    private init() {}

    private var cachedSpots: [Spot] = []
    private var lastDocument: DocumentSnapshot?
    private var lastCacheTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    private let pageSize = FeedFlags.pageSize

    private var isCacheValid: Bool {
        guard let lastTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(lastTime) < cacheValidityDuration
    }

    func getCachedSpots() -> [Spot]? {
        guard !cachedSpots.isEmpty && isCacheValid else { return nil }
        return cachedSpots
    }

    func clearCache() {
        SpotLogger.log(FeedCacheLogs.clearingCache)
        cachedSpots = []
        lastDocument = nil
        lastCacheTime = nil
    }

    func loadInitialSpots() async throws -> [Spot] {
        // If cache is valid, return cached spots
        if let cached = getCachedSpots() {
            SpotLogger.log(FeedCacheLogs.usingCachedFeed, details: ["count": cached.count])
            return cached
        }

        // Otherwise load from Firebase
        SpotLogger.log(FeedCacheLogs.loadingInitialFromFirebase)
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        let snapshot = try await query.getDocuments()
        let fetchedSpots = snapshot.documents.compactMap { doc in
            var spot = try? doc.data(as: Spot.self)
            if spot?.id == nil { spot?.id = doc.documentID }
            return spot
        }

        let spots = await AuthorPrivacyCache.shared.filter(spots: fetchedSpots)

        // Update cache
        cachedSpots = spots
        lastDocument = snapshot.documents.last
        lastCacheTime = Date()

        SpotLogger.log(FeedCacheLogs.loadedAndCached, details: ["count": spots.count])
        return spots
    }

    func loadMoreSpots() async throws -> [Spot] {
        guard let lastDoc = lastDocument else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No more spots to load"])
        }

        SpotLogger.log(FeedCacheLogs.loadingMoreFromFirebase)
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)

        let snapshot = try await query.getDocuments()
        let fetched = snapshot.documents.compactMap { doc in
            var spot = try? doc.data(as: Spot.self)
            if spot?.id == nil { spot?.id = doc.documentID }
            return spot
        }
        let newSpots = await AuthorPrivacyCache.shared.filter(spots: fetched)

        // Update cache with new spots
        cachedSpots.append(contentsOf: newSpots)
        lastDocument = snapshot.documents.last
        lastCacheTime = Date()

        SpotLogger.log(FeedCacheLogs.loadedAndCachedMore, details: ["count": newSpots.count])
        return newSpots
    }

    func refreshFeed() async throws -> [Spot] {
        clearCache()
        return try await loadInitialSpots()
    }

    // Privacy filtering handled by AuthorPrivacyCache
}
