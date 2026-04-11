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
                Task { @MainActor in
                    AnalyticsService.shared.trackUserAction("spot_liked", contentType: "spot", contentId: spotId)
                }
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
                Task { @MainActor in
                    AnalyticsService.shared.trackUserAction("spot_unliked", contentType: "spot", contentId: spotId)
                }
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
                // Increment saves counter on the spot doc (best-effort)
                self.db.collection("spots").document(spotId).updateData([
                    "saves": FieldValue.increment(Int64(1))
                ]) { _ in }
                Task { @MainActor in
                    AnalyticsService.shared.trackUserAction("spot_saved", contentType: "spot", contentId: spotId)
                }
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
                // Decrement saves counter on the spot doc (best-effort)
                self.db.collection("spots").document(spotId).updateData([
                    "saves": FieldValue.increment(Int64(-1))
                ]) { _ in }
                Task { @MainActor in
                    AnalyticsService.shared.trackUserAction("spot_unsaved", contentType: "spot", contentId: spotId)
                }
                completion(.success(()))
            }
        }
    }

    // MARK: - Fetch liked/bookmarked spots
    func fetchUserSpotLists(completion: @escaping (_ liked: [String], _ bookmarked: [String]) -> Void) {
        guard let userId = userId else { completion([], []); return }
        db.collection("users").document(userId).getDocument { snapshot, _ in
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
        let now = FieldValue.serverTimestamp()
        let reqRef = db.collection("users").document(targetUserId).collection("followRequests").document(currentUserId)
        // Write a request doc with denormed fields for list UI
        db.collection("users").document(currentUserId).getDocument { snap, _ in
            let username = snap?.data()? ["username"] as? String ?? ""
            let photoURL = snap?.data()? ["profileImageURL"] as? String ?? ""
            reqRef.setData([
                "requesterUid": currentUserId,
                "createdAt": now,
                "username": username,
                "photoURL": photoURL
            ]) { error in
                if let error = error { completion(.failure(error)) } else { completion(.success(())) }
            }
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
        let reqRef = db.collection("users").document(targetUserId).collection("followRequests").document(currentUserId)
        reqRef.delete { error in
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
            SpotLogger.log(UserSpotServiceLogs.noUserIdAvailable)
            throw NSError(domain: "No user", code: 0)
        }

        SpotLogger.log(UserSpotServiceLogs.fetchingLikedSpots, details: ["userId": userId])

        // Get user's liked and bookmarked spots arrays
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let likedSpotIds = userDoc.data()?["likedSpots"] as? [String] ?? []
        let bookmarkedSpotIds = userDoc.data()?["bookmarkedSpots"] as? [String] ?? []

        SpotLogger.log(UserSpotServiceLogs.foundLikedSpotIds, details: ["count": likedSpotIds.count])

        if likedSpotIds.isEmpty {
            SpotLogger.log(UserSpotServiceLogs.noLikedSpotsFound)
            return PaginatedSpotsResult(spots: [], lastCursor: nil, hasMore: false)
        }

        // For now, we'll use the array-based approach but sort by creation time
        // In a future migration, we could move to subcollections with timestamps
        // Fetch and mark each spot with like/save flags
        var spots = try await fetchSpotsByIds(likedSpotIds)
        let likedSet = Set(likedSpotIds)
        let savedSet = Set(bookmarkedSpotIds)
        spots = spots.map { s in
            var m = s
            if let id = m.id {
                m.isLiked = likedSet.contains(id)
                m.isSaved = savedSet.contains(id)
            }
            return m
        }

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

        // Get user's bookmarked and liked spots arrays
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let bookmarkedSpotIds = userDoc.data()?["bookmarkedSpots"] as? [String] ?? []
        let likedSpotIds = userDoc.data()?["likedSpots"] as? [String] ?? []

        if bookmarkedSpotIds.isEmpty {
            return PaginatedSpotsResult(spots: [], lastCursor: nil, hasMore: false)
        }

        // For now, we'll use the array-based approach but sort by creation time
        // Fetch and mark each spot with like/save flags
        var spots = try await fetchSpotsByIds(bookmarkedSpotIds)
        let savedSet = Set(bookmarkedSpotIds)
        let likedSet = Set(likedSpotIds)
        spots = spots.map { s in
            var m = s
            if let id = m.id {
                m.isSaved = savedSet.contains(id)
                m.isLiked = likedSet.contains(id)
            }
            return m
        }

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
                        SpotLogger.log(UserSpotServiceLogs.fetchSpotFailed, details: ["spotId": spotId, "error": error.localizedDescription])
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
