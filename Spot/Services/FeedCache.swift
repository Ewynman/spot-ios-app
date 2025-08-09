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
    private let pageSize = 10
    
    private var isCacheValid: Bool {
        guard let lastTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(lastTime) < cacheValidityDuration
    }
    
    func getCachedSpots() -> [Spot]? {
        guard !cachedSpots.isEmpty && isCacheValid else { return nil }
        return cachedSpots
    }
    
    func clearCache() {
        SpotLogger.debug("Clearing feed cache")
        cachedSpots = []
        lastDocument = nil
        lastCacheTime = nil
    }
    
    func loadInitialSpots() async throws -> [Spot] {
        // If cache is valid, return cached spots
        if let cached = getCachedSpots() {
            SpotLogger.info("Using cached feed: \(cached.count) spots")
            return cached
        }
        
        // Otherwise load from Firebase
        SpotLogger.debug("Loading initial feed from Firebase")
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        
        let snapshot = try await query.getDocuments()
        let fetchedSpots = snapshot.documents.compactMap { doc in
            try? doc.data(as: Spot.self)
        }

        let spots = try await filterSpotsForPrivacy(fetchedSpots)
        
        // Update cache
        cachedSpots = spots
        lastDocument = snapshot.documents.last
        lastCacheTime = Date()
        
        SpotLogger.info("Loaded and cached \(spots.count) spots")
        return spots
    }
    
    func loadMoreSpots() async throws -> [Spot] {
        guard let lastDoc = lastDocument else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No more spots to load"])
        }
        
        SpotLogger.debug("Loading more spots from Firebase")
        let query = Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
        
        let snapshot = try await query.getDocuments()
        let fetched = snapshot.documents.compactMap { doc in
            try? doc.data(as: Spot.self)
        }
        let newSpots = try await filterSpotsForPrivacy(fetched)
        
        // Update cache with new spots
        cachedSpots.append(contentsOf: newSpots)
        lastDocument = snapshot.documents.last
        lastCacheTime = Date()
        
        SpotLogger.info("Loaded and cached \(newSpots.count) more spots")
        return newSpots
    }
    
    func refreshFeed() async throws -> [Spot] {
        clearCache()
        return try await loadInitialSpots()
    }

    // MARK: - Privacy Filtering
    private func filterSpotsForPrivacy(_ spots: [Spot]) async throws -> [Spot] {
        // If no current user, only show public users' spots
        let currentUserId = Auth.auth().currentUser?.uid

        // Short-circuit: nothing to filter
        guard !spots.isEmpty else { return spots }

        // Gather unique author IDs
        let authorIds = Set(spots.compactMap { $0.userId })

        // Fetch viewer following list
        var following: Set<String> = []
        if let currentUserId {
            let viewerDoc = try await Firestore.firestore().collection("users").document(currentUserId).getDocument()
            let arr = viewerDoc.data()? ["following"] as? [String] ?? []
            following = Set(arr)
        }

        // Fetch isPrivate for all authors concurrently
        let authorPrivacy: [String: Bool] = try await withThrowingTaskGroup(of: (String, Bool).self) { group in
            for authorId in authorIds {
                group.addTask {
                    let snapshot = try await Firestore.firestore().collection("users").document(authorId).getDocument()
                    let isPrivate = snapshot.data()? ["isPrivate"] as? Bool ?? false
                    return (authorId, isPrivate)
                }
            }
            var result: [String: Bool] = [:]
            for try await (authorId, isPrivate) in group {
                result[authorId] = isPrivate
            }
            return result
        }

        // Build allowlist: public users, followed users, and self
        var allowedUserIds: Set<String> = []
        for (authorId, isPrivate) in authorPrivacy {
            if !isPrivate {
                allowedUserIds.insert(authorId)
            }
        }
        allowedUserIds.formUnion(following)
        if let currentUserId { allowedUserIds.insert(currentUserId) }

        // Filter
        let filtered = spots.filter { spot in
            guard let uid = spot.userId else { return false }
            return allowedUserIds.contains(uid)
        }

        return filtered
    }
} 