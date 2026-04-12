//
//  SpotService.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

final class SpotService {
    static let shared = SpotService()
    private init() {}

    private var cachedSpots: [Spot] = []
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    private var isCacheValid: Bool {
        guard let lastFetch = lastFetchTime else { return false }
        return Date().timeIntervalSince(lastFetch) < cacheValidityDuration
    }

    func createSpot(imageURL: String, latitude: Double, longitude: Double, vibeTag: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."])))
            return
        }

        let data: [String: Any] = [
            "userId": userId,
            "imageURL": imageURL,
            "latitude": latitude,
            "longitude": longitude,
            "vibeTag": vibeTag,
            "createdAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore().collection("spots").addDocument(data: data) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func fetchSpotsForMap(forceRefresh: Bool = false, completion: @escaping (Result<[Spot], Error>) -> Void) {
        // Return cached spots if available and cache is still valid
        if !forceRefresh && !cachedSpots.isEmpty && isCacheValid {
            SpotLogger.log(SpotServiceLogs.cachedSpotsReturned, details: ["count": cachedSpots.count])
            completion(.success(cachedSpots))
            return
        }

        SpotLogger.log(SpotServiceLogs.fetchSpotsStarted, details: ["orderBy": "createdAt", "desc": true])
        Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .limit(to: 1000)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    SpotLogger.log(SpotServiceLogs.fetchSpotsError, details: ["error": error.localizedDescription])
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    SpotLogger.log(SpotServiceLogs.fetchSpotsEmpty)
                    completion(.success([]))
                    return
                }

                let spots = documents.compactMap { document -> Spot? in
                    let data = document.data()
                    SpotLogger.log(SpotServiceLogs.spotDocParsed, details: ["docId": document.documentID])
                    guard let userId = data["userId"] as? String,
                          let imageURL = data["imageURL"] as? String,
                          let latitude = data["latitude"] as? Double,
                          let longitude = data["longitude"] as? Double else {
                        SpotLogger.log(SpotServiceLogs.spotDocSkipped, details: ["docId": document.documentID])
                        return nil
                    }
                    return Spot(
                        id: document.documentID,
                        userId: userId,
                        username: data["username"] as? String ?? "Unknown",
                        userProfileImageURL: data["userProfileImageURL"] as? String,
                        imageURL: imageURL,
                        vibeTag: data["vibeTag"] as? String ?? "",
                        latitude: latitude,
                        longitude: longitude,
                        locationName: data["locationName"] as? String,
                        likes: data["likes"] as? Int ?? 0,
                        isLiked: data["isLiked"] as? Bool ?? false,
                        isSaved: data["isSaved"] as? Bool ?? false,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                        authorIsPrivate: data["authorIsPrivate"] as? Bool
                    )
                }

                // Apply privacy filter on the map
                Task {
                    do {
                        let filtered = await AuthorPrivacyCache.shared.filter(spots: spots)
                        self?.cachedSpots = filtered
                        self?.lastFetchTime = Date()
                        SpotLogger.log(SpotServiceLogs.spotsCachedForMap, details: ["count": filtered.count])
                        completion(.success(filtered))
                    }
                }
            }
    }

    // MARK: - Fetch Single Spot

    func fetchSpotById(_ spotId: String, completion: @escaping (Result<Spot?, Error>) -> Void) {
        SpotLogger.log(SpotServiceLogs.fetchSpotByIdStarted, details: ["spotId": spotId])

        let docRef = Firestore.firestore().collection("spots").document(spotId)
        docRef.getDocument { [weak self] document, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let document = document, document.exists else {
                SpotLogger.log(SpotServiceLogs.spotNotFound, details: ["spotId": spotId])
                completion(.success(nil))
                return
            }

            let data = document.data() ?? [:]

            // Check if user is blocked
            if let userId = data["userId"] as? String {
                self?.checkIfUserIsBlocked(userId) { isBlocked in
                    if isBlocked {
                        SpotLogger.log(SpotServiceLogs.spotOwnerBlocked, details: ["spotId": spotId])
                        completion(.success(nil))
                        return
                    }

                    self?.processSpotData(data, spotId: spotId, completion: completion)
                }
            } else {
                self?.processSpotData(data, spotId: spotId, completion: completion)
            }
        }
    }

    /// Async/await wrapper for existing callback API.
    func fetchSpotById(_ spotId: String) async throws -> Spot? {
        try await withCheckedThrowingContinuation { continuation in
            fetchSpotById(spotId) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func processSpotData(_ data: [String: Any], spotId: String, completion: @escaping (Result<Spot?, Error>) -> Void) {
        guard let userId = data["userId"] as? String,
              let imageURL = data["imageURL"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else {
            SpotLogger.log(SpotServiceLogs.invalidSpotData, details: ["spotId": spotId])
            completion(.success(nil))
            return
        }

        let spot = Spot(
            id: spotId,
            userId: userId,
            username: data["username"] as? String ?? "Unknown",
            userProfileImageURL: data["userProfileImageURL"] as? String,
            imageURL: imageURL,
            vibeTag: data["vibeTag"] as? String ?? "",
            latitude: latitude,
            longitude: longitude,
            locationName: data["locationName"] as? String,
            likes: data["likes"] as? Int ?? 0,
            isLiked: data["isLiked"] as? Bool ?? false,
            isSaved: data["isSaved"] as? Bool ?? false,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            authorIsPrivate: data["authorIsPrivate"] as? Bool
        )

        SpotLogger.log(SpotServiceLogs.spotFetched, details: ["spotId": spotId])
        completion(.success(spot))
    }

    private func checkIfUserIsBlocked(_ userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        Firestore.firestore().collection("users").document(currentUserId).getDocument { document, error in
            if let error = error {
                SpotLogger.log(SpotServiceLogs.blockedUsersCheckFailed, details: ["error": error.localizedDescription])
                completion(false)
                return
            }

            let blockedUsers = document?.data()?["blockedUsers"] as? [String] ?? []
            completion(blockedUsers.contains(userId))
        }
    }

    // MARK: - Delete Spot
    func deleteSpot(_ spot: Spot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = spot.id else {
            completion(.failure(NSError(domain: "SpotService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing spot id; cannot delete"])))
            return
        }
        let docRef = Firestore.firestore().collection("spots").document(id)

        // Delete Firestore document first
        docRef.delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Best-effort delete of main image
            if let urlString = spot.imageURL {
                self.deleteStorageIfPossible(fromDownloadURL: urlString)
            }
            // Best-effort delete of thumbnail if distinct
            if let thumbString = spot.thumbnailURL, thumbString != spot.imageURL {
                self.deleteStorageIfPossible(fromDownloadURL: thumbString)
            }

            completion(.success(()))
        }
    }

    /// Async/await wrapper for existing callback API.
    func deleteSpot(_ spot: Spot) async throws {
        try await withCheckedThrowingContinuation { continuation in
            deleteSpot(spot) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deleteStorageIfPossible(fromDownloadURL urlString: String) {
        // Parse the Firebase Storage object path from the download URL
        // URL form: https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<ENCODED_PATH>?alt=media&token=...
        guard let url = URL(string: urlString) else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard let pathIndex = comps.path.range(of: "/o/") else { return }
        let encodedPath = String(comps.path[pathIndex.upperBound...])
        let rawPath = encodedPath.removingPercentEncoding ?? encodedPath
        guard !rawPath.isEmpty else { return }
        let ref = Storage.storage().reference(withPath: rawPath)
        ref.delete { error in
            if let error = error {
                SpotLogger.log(SpotServiceLogs.storageDeleteFailed, details: ["path": rawPath, "error": error.localizedDescription])
            } else {
                SpotLogger.log(SpotServiceLogs.storageDeleted, details: ["path": rawPath])
            }
        }
    }
}
