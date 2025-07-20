import Foundation
import FirebaseFirestore

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
        let spots = snapshot.documents.compactMap { doc in
            try? doc.data(as: Spot.self)
        }
        
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
        let newSpots = snapshot.documents.compactMap { doc in
            try? doc.data(as: Spot.self)
        }
        
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
} 