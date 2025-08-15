import Foundation
import FirebaseAuth
import FirebaseFirestore

class UserSpotService {
    static let shared = UserSpotService()
    private let db = Firestore.firestore()
    private var userId: String? { Auth.auth().currentUser?.uid }
    
    // MARK: - Like/Unlike
    func likeSpot(spotId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let userRef = db.collection("users").document(userId)
        userRef.updateData([
            "likedSpots": FieldValue.arrayUnion([spotId])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func unlikeSpot(spotId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let userRef = db.collection("users").document(userId)
        userRef.updateData([
            "likedSpots": FieldValue.arrayRemove([spotId])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Bookmark/Unbookmark
    func bookmarkSpot(spotId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let userRef = db.collection("users").document(userId)
        userRef.updateData([
            "bookmarkedSpots": FieldValue.arrayUnion([spotId])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func unbookmarkSpot(spotId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let userRef = db.collection("users").document(userId)
        userRef.updateData([
            "bookmarkedSpots": FieldValue.arrayRemove([spotId])
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Fetch liked/bookmarked spots
    func fetchUserSpotLists(completion: @escaping (_ liked: [String], _ bookmarked: [String]) -> Void) {
        guard let userId = userId else { completion([], []); return }
        db.collection("users").document(userId).getDocument { snapshot, error in
            let liked = snapshot?.data()? ["likedSpots"] as? [String] ?? []
            let bookmarked = snapshot?.data()? ["bookmarkedSpots"] as? [String] ?? []
            completion(liked, bookmarked)
        }
    }

    // MARK: - Follow / Request Follow
    func follow(userId targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUserId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let currentUserRef = db.collection("users").document(currentUserId)
        currentUserRef.updateData([
            "following": FieldValue.arrayUnion([targetUserId]),
            "requestedFollows": FieldValue.arrayRemove([targetUserId])
        ]) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func requestFollow(userId targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUserId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let currentUserRef = db.collection("users").document(currentUserId)
        currentUserRef.updateData([
            "requestedFollows": FieldValue.arrayUnion([targetUserId])
        ]) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func getSocialLists(for userId: String? = nil, completion: @escaping (_ following: [String], _ requestedFollows: [String]) -> Void) {
        let uid = userId ?? self.userId
        guard let uid else { completion([], []); return }
        db.collection("users").document(uid).getDocument { snapshot, _ in
            let following = snapshot?.data()? ["following"] as? [String] ?? []
            let requested = snapshot?.data()? ["requestedFollows"] as? [String] ?? []
            completion(following, requested)
        }
    }

    func unfollow(userId targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUserId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let currentUserRef = db.collection("users").document(currentUserId)
        currentUserRef.updateData([
            "following": FieldValue.arrayRemove([targetUserId])
        ]) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func cancelFollowRequest(userId targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUserId = userId else { completion(.failure(NSError(domain: "No user", code: 0))); return }
        let currentUserRef = db.collection("users").document(currentUserId)
        currentUserRef.updateData([
            "requestedFollows": FieldValue.arrayRemove([targetUserId])
        ]) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }
    
    // MARK: - New Paginated Likes/Bookmarks (using existing array schema)
    
    struct PaginatedSpotsResult {
        let spots: [Spot]
        let lastCursor: DocumentSnapshot?
        let hasMore: Bool
    }
    
    func fetchLikedSpots(pageSize: Int = 24, lastCursor: DocumentSnapshot? = nil) async throws -> PaginatedSpotsResult {
        guard let userId = userId else {
            SpotLogger.error("UserSpotService: No user ID available")
            throw NSError(domain: "No user", code: 0)
        }
        
        SpotLogger.info("UserSpotService: Fetching liked spots for user: \(userId)")
        
        // Get user's liked spots array
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let likedSpotIds = userDoc.data()?["likedSpots"] as? [String] ?? []
        
        SpotLogger.info("UserSpotService: Found \(likedSpotIds.count) liked spot IDs")
        
        if likedSpotIds.isEmpty {
            SpotLogger.info("UserSpotService: No liked spots found")
            return PaginatedSpotsResult(spots: [], lastCursor: nil, hasMore: false)
        }
        
        // For now, we'll use the array-based approach but sort by creation time
        // In a future migration, we could move to subcollections with timestamps
        let spots = try await fetchSpotsByIds(likedSpotIds)
        
        // Sort by createdAt descending (most recent first)
        let sortedSpots = spots.sorted { (spot1, spot2) in
            (spot1.createdAt ?? Date.distantPast) > (spot2.createdAt ?? Date.distantPast)
        }
        
        // Simple pagination - return all spots for now since we're using arrays
        // In production with subcollections, you'd implement proper cursor-based pagination
        let hasMore = false // No pagination for array-based approach
        
        return PaginatedSpotsResult(
            spots: sortedSpots,
            lastCursor: nil,
            hasMore: hasMore
        )
    }
    
    func fetchBookmarkedSpots(pageSize: Int = 24, lastCursor: DocumentSnapshot? = nil) async throws -> PaginatedSpotsResult {
        guard let userId = userId else {
            throw NSError(domain: "No user", code: 0)
        }
        
        // Get user's bookmarked spots array
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let bookmarkedSpotIds = userDoc.data()?["bookmarkedSpots"] as? [String] ?? []
        
        if bookmarkedSpotIds.isEmpty {
            return PaginatedSpotsResult(spots: [], lastCursor: nil, hasMore: false)
        }
        
        // For now, we'll use the array-based approach but sort by creation time
        let spots = try await fetchSpotsByIds(bookmarkedSpotIds)
        
        // Sort by createdAt descending (most recent first)
        let sortedSpots = spots.sorted { (spot1, spot2) in
            (spot1.createdAt ?? Date.distantPast) > (spot2.createdAt ?? Date.distantPast)
        }
        
        // Simple pagination - return all spots for now since we're using arrays
        // In production with subcollections, you'd implement proper cursor-based pagination
        let hasMore = false // No pagination for array-based approach
        
        return PaginatedSpotsResult(
            spots: sortedSpots,
            lastCursor: nil,
            hasMore: hasMore
        )
    }
    
    private func fetchSpotsByIds(_ spotIds: [String]) async throws -> [Spot] {
        guard !spotIds.isEmpty else { return [] }
        
        // Batch fetch spots
        let spotsRef = db.collection("spots")
        let spots = try await withThrowingTaskGroup(of: Spot?.self) { group in
            for spotId in spotIds {
                group.addTask {
                    do {
                        let doc = try await spotsRef.document(spotId).getDocument()
                        guard doc.exists else { return nil }
                        var spot = try doc.data(as: Spot.self)
                        spot.id = doc.documentID // Ensure ID is populated
                        return spot
                    } catch {
                        SpotLogger.error("Failed to fetch spot \(spotId): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            var results: [Spot] = []
            for try await spot in group {
                if let spot = spot {
                    results.append(spot)
                }
            }
            return results
        }
        
        // Filter out blocked users' spots
        let currentUserId = Auth.auth().currentUser?.uid
        if let currentUserId {
            let userDoc = try await db.collection("users").document(currentUserId).getDocument()
            let blockedUsers = userDoc.data()?["blockedUsers"] as? [String] ?? []
            
            return spots.filter { spot in
                guard let spotUserId = spot.userId else { return false }
                return !blockedUsers.contains(spotUserId)
            }
        }
        
        return spots
    }
}