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
}