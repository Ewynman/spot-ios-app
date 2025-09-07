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
            SpotLogger.info("Returning cached spots", details: ["count": cachedSpots.count])
            completion(.success(cachedSpots))
            return
        }

        SpotLogger.debug("Fetch spots for map", details: ["orderBy": "createdAt", "desc": true])
        Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    SpotLogger.error("fetchSpotsForMap error", details: ["error": error.localizedDescription])
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    SpotLogger.warning("fetchSpotsForMap no documents", details: [:])
                    completion(.success([]))
                    return
                }

                let spots = documents.compactMap { document -> Spot? in
                    let data = document.data()
                    SpotLogger.debug("Parsing spot doc", details: ["docId": document.documentID])
                    guard let userId = data["userId"] as? String,
                          let imageURL = data["imageURL"] as? String,
                          let latitude = data["latitude"] as? Double,
                          let longitude = data["longitude"] as? Double else {
                        SpotLogger.warning("Skipping doc due to missing fields", details: ["docId": document.documentID])
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
                        SpotLogger.info("Parsed and cached spots (map)", details: ["count": filtered.count])
                        completion(.success(filtered))
                    }
                }
            }
    }

    // MARK: - Fetch Single Spot

    func fetchSpotById(_ spotId: String) async throws -> Spot? {
        SpotLogger.debug("Fetch spot by ID", details: ["spotId": spotId])

        let docRef = Firestore.firestore().collection("spots").document(spotId)
        let document = try await docRef.getDocument()

        guard document.exists else {
            SpotLogger.warning("Spot not found", details: ["spotId": spotId])
            return nil
        }

        let data = document.data() ?? [:]

        // Check if user is blocked
        if let userId = data["userId"] as? String {
            let isBlocked = await checkIfUserIsBlocked(userId)
            if isBlocked {
                SpotLogger.info("Spot owner blocked (returning nil)", details: ["spotId": spotId])
                return nil
            }
        }

        guard let userId = data["userId"] as? String,
              let imageURL = data["imageURL"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else {
            SpotLogger.error("Invalid spot data", details: ["spotId": spotId])
            return nil
        }

        let spot = Spot(
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

        SpotLogger.info("Fetched spot", details: ["spotId": spotId])
        return spot
    }

    private func checkIfUserIsBlocked(_ userId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }

        do {
            let userDoc = try await Firestore.firestore().collection("users").document(currentUserId).getDocument()
            let blockedUsers = userDoc.data()?["blockedUsers"] as? [String] ?? []
            return blockedUsers.contains(userId)
        } catch {
            SpotLogger.error("Failed to check blocked users", details: ["error": error.localizedDescription])
            return false
        }
    }

    // MARK: - Delete Spot
    func deleteSpot(_ spot: Spot) async throws {
        guard let id = spot.id else {
            throw NSError(domain: "SpotService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing spot id; cannot delete"]) }
        let docRef = Firestore.firestore().collection("spots").document(id)

        // Delete Firestore document first
        try await docRef.delete()

        // Best-effort delete of main image
        if let urlString = spot.imageURL {
            deleteStorageIfPossible(fromDownloadURL: urlString)
        }
        // Best-effort delete of thumbnail if distinct
        if let thumbString = spot.thumbnailURL, thumbString != spot.imageURL {
            deleteStorageIfPossible(fromDownloadURL: thumbString)
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
                SpotLogger.warning("Storage delete failed", details: ["path": rawPath, "error": error.localizedDescription])
            } else {
                SpotLogger.info("Storage deleted", details: ["path": rawPath])
            }
        }
    }
}
