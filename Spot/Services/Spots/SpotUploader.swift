//
//  SpotUploader.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import CoreLocation
import FirebaseStorage
import FirebaseAuth
import UIKit

final class SpotUploader {
    static let shared = SpotUploader()
    private init() {}

    static func incrementUserVibeStat(userId: String, vibeTag: String) {
        SpotLogger.debug("Increment vibe stat", details: ["userId": userId, "vibe": vibeTag])
        let userRef = Firestore.firestore().collection("users").document(userId)

        userRef.getDocument { snapshot, error in
            if let error = error {
                SpotLogger.error("Vibe stats: failed to get user doc", details: ["error": error.localizedDescription])
                return
            }

            guard let data = snapshot?.data() else {
                SpotLogger.error("Vibe stats: no user data", details: ["userId": userId])
                return
            }

            // Get existing vibeStats or create new
            var vibeStats = data["vibeStats"] as? [String: Int] ?? [:]

            // Increment the count for this vibe
            vibeStats[vibeTag] = (vibeStats[vibeTag] ?? 0) + 1

            // Update the user document
            userRef.updateData([
                "vibeStats": vibeStats
            ]) { error in
                if let error = error {
                    SpotLogger.error("Vibe stats update failed", details: ["userId": userId, "vibe": vibeTag, "error": error.localizedDescription])
                } else {
                    SpotLogger.info("Vibe stats updated", details: ["userId": userId, "vibe": vibeTag, "count": vibeStats[vibeTag] ?? 1])
                }
            }
        }
    }

    private func getCurrentUserData(completion: @escaping (Result<(String, String?), Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.unauthorized, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                SpotLogger.error("Fetch user data failed", details: ["error": error.localizedDescription])
                completion(.failure(error))
                return
            }

            guard let data = snapshot?.data(),
                  let username = data["username"] as? String else {
                SpotLogger.error("Invalid user data format", details: ["uid": uid])
                completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.badRequest, userInfo: [NSLocalizedDescriptionKey: "Invalid user data"])))
                return
            }

            let profileImageURL = data["profileImageURL"] as? String
            completion(.success((username, profileImageURL)))
        }
    }

    func uploadSpot(
        image: UIImage,
        vibeTag: String,
        latitude: Double,
        longitude: Double,
        placeName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.unauthorized, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            SpotLogger.error("User not authenticated for spot upload", details: [:])
            return
        }

        // First get current user data
        getCurrentUserData { [weak self] result in
            switch result {
            case .success(let userData):
                let (username, profileImageURL) = userData
                self?.performSpotUpload(
                    image: image,
                    vibeTag: vibeTag,
                    latitude: latitude,
                    longitude: longitude,
                    placeName: placeName,
                    userId: userId,
                    username: username,
                    userProfileImageURL: profileImageURL,
                    completion: completion
                )
            case .failure(let error):
                SpotLogger.error("Get user data failed", details: ["error": error.localizedDescription])
                completion(.failure(error))
            }
        }
    }

    func uploadSpot(
        images: [UIImage],
        vibeTag: String,
        latitude: Double,
        longitude: Double,
        placeName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.unauthorized, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            SpotLogger.error("User not authenticated for spot upload", details: [:])
            return
        }

        // First get current user data
        getCurrentUserData { [weak self] result in
            switch result {
            case .success(let userData):
                let (username, profileImageURL) = userData
                self?.performMultiSpotUpload(
                    images: images,
                    vibeTag: vibeTag,
                    latitude: latitude,
                    longitude: longitude,
                    placeName: placeName,
                    userId: userId,
                    username: username,
                    userProfileImageURL: profileImageURL,
                    completion: completion
                )
            case .failure(let error):
                SpotLogger.error("Get user data failed", details: ["error": error.localizedDescription])
                completion(.failure(error))
            }
        }
    }

    // MARK: - Update spot (replace metadata, optionally images)
    func updateSpot(
        spotId: String,
        images: [UIImage]?,
        vibeTag: String,
        latitude: Double,
        longitude: Double,
        placeName: String
    ) async throws {
        let db = Firestore.firestore()

        var updates: [String: Any] = [
            "vibeTag": vibeTag,
            "vibeTag_lower": vibeTag.lowercased(),
            "latitude": latitude,
            "longitude": longitude,
            "geohash": GeoHash.encode(latitude: latitude, longitude: longitude, precision: 7),
            "locationName": placeName,
            "locationName_lower": placeName.lowercased(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let images, !images.isEmpty {
            let limited = Array(images.prefix(5))
            var urls: [String] = []
            for (idx, image) in limited.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
                let filename = "spot_\(spotId)_upd_\(idx).jpg"
                let storageRef = Storage.storage().reference().child("spots/\(filename)")
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                metadata.customMetadata = [
                    "spotId": spotId,
                    "index": "\(idx)",
                    "source": "ios"
                ]
                _ = try await storageRef.putDataAsync(data, metadata: metadata)
                let url = try await storageRef.downloadURL()
                urls.append(url.absoluteString)
            }
            if let first = urls.first {
                updates["imageURL"] = first
                updates["thumbnailURL"] = first
            }
            updates["imageURLs"] = urls
        }

        try await db.collection("spots").document(spotId).setData(updates, merge: true)
        SpotLogger.info("Spot updated", details: ["spotId": spotId])
    }

    private func performMultiSpotUpload(
        images: [UIImage],
        vibeTag: String,
        latitude: Double,
        longitude: Double,
        placeName: String,
        userId: String,
        username: String,
        userProfileImageURL: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let limited = Array(images.prefix(5))
        let postId = UUID().uuidString
        let storage = Storage.storage()

        // Upload images sequentially to avoid memory spikes
        Task {
            var urls: [String] = []
            for (idx, image) in limited.enumerated() {
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.badRequest, userInfo: [NSLocalizedDescriptionKey: "Image conversion failed."]))); return
                }
                let filename = "spot_\(postId)_\(idx).jpg"
                let storageRef = storage.reference().child("spots/\(filename)")
                do {
                    let metadata = StorageMetadata()
                    metadata.contentType = "image/jpeg"
                    metadata.customMetadata = [
                        "spotId": postId,
                        "userId": userId,
                        "index": "\(idx)",
                        "source": "ios"
                    ]
                    _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
                    let url = try await storageRef.downloadURL()
                    urls.append(url.absoluteString)
                } catch {
                    SpotLogger.error("Multi upload error", details: ["error": error.localizedDescription])
                    completion(.failure(error))
                    return
                }
            }

            // Reverse geocode to finalize location name
            let geocoder = CLGeocoder()
            let loc = CLLocation(latitude: latitude, longitude: longitude)
            var finalLocationName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalLocationName.isEmpty {
                if let pm = try? await geocoder.reverseGeocodeLocation(loc).first {
                    if let name = pm.name, !name.isEmpty { finalLocationName = name } else if let city = pm.locality, let state = pm.administrativeArea { finalLocationName = "\(city), \(state)" }
                }
            }

            let geohash = GeoHash.encode(latitude: latitude, longitude: longitude, precision: 7)
            // NOTE: imageURLs is intentionally excluded from the initial setData payload.
            // The deployed Firestore create rule has a field allow-list that predates the
            // imageURLs field — including it causes the create to be rejected with
            // "Missing or insufficient permissions."  We write it in a separate updateData
            // call immediately after, which goes through the owner-update path (no field
            // restrictions for the document owner).
            var data: [String: Any] = [
                "postId": postId,
                "userId": userId,
                "username": username,
                "userProfileImageURL": userProfileImageURL ?? "",
                "imageURL": urls.first ?? "",
                "thumbnailURL": urls.first ?? "",
                "caption": "",
                "vibeTag": vibeTag,
                "vibeTag_lower": vibeTag.lowercased(),
                "latitude": latitude,
                "longitude": longitude,
                "geohash": geohash,
                "locationName": finalLocationName,
                "locationName_lower": finalLocationName.lowercased(),
                "likes": 0,
                "saves": 0,
                "createdAt": FieldValue.serverTimestamp()
            ]

            // Run all Firestore operations on @MainActor to match the single-image upload path.
            Task { @MainActor in
                // Denormalize author's privacy (matches single-image path)
                var finalData = data
                do {
                    let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                    if let isPrivate = userDoc.data()?["isPrivate"] as? Bool { finalData["authorIsPrivate"] = isPrivate }
                } catch {
                    SpotLogger.debug(.network, "Failed to denormalize authorIsPrivate", details: ["error": error.localizedDescription])
                }

                // Ensure the vibe tag exists globally (non-blocking)
                Task { try? await VibeTagService.shared.ensureTagExists(name: vibeTag) }

                let db = Firestore.firestore()
                let docRef = db.collection("spots").document(postId)
                var docCreated = false

                // Force-refresh the Firebase ID token on MainActor so the Firestore write
                // stream picks up the latest auth credentials (including email_verified claim)
                // before the write.  Multi-image uploads take significantly longer than
                // single-image ones, creating a window where the SDK's cached token can
                // become stale or be mid-refresh when setData is called.
                var tokenEmailVerified: Bool = false
                if let user = Auth.auth().currentUser {
                    do {
                        let tokenResult = try await user.getIDTokenResult(forcingRefresh: true)
                        tokenEmailVerified = tokenResult.claims["email_verified"] as? Bool ?? false
                    } catch {
                        SpotLogger.error("Token refresh failed before Firestore write", details: [
                            "postId": postId,
                            "uid": Auth.auth().currentUser?.uid ?? "nil",
                            "error": error.localizedDescription
                        ])
                    }
                }
                let preWriteUser = Auth.auth().currentUser
                SpotLogger.info("setData pre-write", details: [
                    "postId": postId,
                    "uid": preWriteUser?.uid ?? "nil",
                    "docUserId": userId,
                    "isEmailVerified": preWriteUser?.isEmailVerified ?? false,
                    "tokenEmailVerified": tokenEmailVerified,
                    "isAnonymous": preWriteUser?.isAnonymous ?? true,
                    "fieldKeys": Array(finalData.keys).sorted().joined(separator: ", ")
                ])
                do {
                    // Step 1: create the document without imageURLs (passes the create rule)
                    try await docRef.setData(finalData)
                    docCreated = true
                    SpotLogger.info("setData step 1 succeeded", details: ["postId": postId])
                    // Step 2: attach imageURLs via owner update (owner can write any field)
                    try await docRef.updateData(["imageURLs": urls])
                    SpotLogger.info("Spot created (multi)", details: ["postId": postId, "count": urls.count])
                    completion(.success(()))
                } catch {
                    let nsErr = error as NSError
                    SpotLogger.error("Create spot document failed", details: [
                        "postId": postId,
                        "failedStep": docCreated ? "updateData (step 2)" : "setData (step 1)",
                        "errorDomain": nsErr.domain,
                        "errorCode": nsErr.code,
                        "error": nsErr.localizedDescription,
                        "uid": Auth.auth().currentUser?.uid ?? "nil",
                        "docUserId": userId,
                        "isEmailVerified": Auth.auth().currentUser?.isEmailVerified ?? false
                    ])
                    // Attempt to clean up any orphaned resources
                    Task {
                        // Remove the Firestore document if it was already created (step 2 failed)
                        if docCreated {
                            do {
                                try await docRef.delete()
                            } catch {
                                SpotLogger.debug(.network, "Failed to clean up orphaned spot document", details: ["postId": postId, "error": error.localizedDescription])
                            }
                        }
                        // Remove uploaded Storage images
                        var cleanedCount = 0
                        for (idx, _) in limited.enumerated() {
                            let filename = "spot_\(postId)_\(idx).jpg"
                            let ref = storage.reference().child("spots/\(filename)")
                            do {
                                try await ref.delete()
                                cleanedCount += 1
                            } catch {
                                SpotLogger.debug(.network, "Failed to clean up orphaned image", details: ["postId": postId, "index": idx, "error": error.localizedDescription])
                            }
                        }
                        if cleanedCount > 0 {
                            SpotLogger.debug("Cleaned up \(cleanedCount) orphaned image(s)", details: ["postId": postId])
                        }
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    private func performSpotUpload(
        image: UIImage,
        vibeTag: String,
        latitude: Double,
        longitude: Double,
        placeName: String,
        userId: String,
        username: String,
        userProfileImageURL: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Compress the image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image conversion failed."])))
            SpotLogger.error("Image conversion failed for spot upload", details: [:])
            return
        }

        let postId = UUID().uuidString
        let filename = "spot_\(postId).jpg"
        let storageRef = Storage.storage().reference().child("spots/\(filename)")

        SpotLogger.info("Uploading spot image to Firebase Storage", details: ["filename": filename])
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "spotId": postId,
            "userId": userId,
            "index": "0",
            "source": "ios"
        ]
        storageRef.putData(imageData, metadata: metadata) { _, error in
            if let error = error {
                SpotLogger.error("Upload spot image failed", details: ["error": error.localizedDescription])
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    SpotLogger.error("Get download URL failed", details: ["error": error.localizedDescription])
                    completion(.failure(error))
                    return
                }

                guard let imageUrl = url?.absoluteString else {
                    SpotLogger.error("Download URL nil after image upload", details: [:])
                    completion(.failure(NSError(domain: "", code: Constants.HTTPErrorCode.internalServerError, userInfo: [NSLocalizedDescriptionKey: "URL not found."])))
                    return
                }

                SpotLogger.info("Image uploaded; generating thumbnail and reverse geocoding", details: ["postId": postId])
                // Generate a simple client-side thumbnail URL alias (server/CDN can replace later)
                let thumbURL = imageUrl // Placeholder: same URL for now
                let geocoder = CLGeocoder()
                let loc = CLLocation(latitude: latitude, longitude: longitude)
                geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
                    let trimmedPlace = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let pm = placemarks?.first
                    let pmName = pm?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let city = pm?.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let state = pm?.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cityState = [city, state].compactMap { $0 }.joined(separator: ", ")
                    // Priority: user-selected placeName > placemark.name > City, State
                    let finalLocationName: String
                    if !trimmedPlace.isEmpty {
                        finalLocationName = trimmedPlace
                    } else if let pmName, !pmName.isEmpty {
                        finalLocationName = pmName
                    } else {
                        finalLocationName = cityState
                    }

                    let geohash = GeoHash.encode(latitude: latitude, longitude: longitude, precision: 7)
                    var data: [String: Any] = [
                        "postId": postId,
                        "userId": userId,
                        "username": username,
                        "userProfileImageURL": userProfileImageURL ?? "",
                        "imageURL": imageUrl,
                        "thumbnailURL": thumbURL,
                        "caption": "",
                        "vibeTag": vibeTag,
                        "vibeTag_lower": vibeTag.lowercased(),
                        "latitude": latitude,
                        "longitude": longitude,
                        "geohash": geohash,
                        "locationName": finalLocationName,
                        "locationName_lower": finalLocationName.lowercased(),
                        "likes": 0,
                        "saves": 0,
                        "createdAt": FieldValue.serverTimestamp()
                    ]

                    // Denormalize author's current privacy snapshot and create document atomically
                    Task { @MainActor in
                        do {
                            let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                            if let isPrivate = userDoc.data()? ["isPrivate"] as? Bool {
                                data["authorIsPrivate"] = isPrivate
                            }
                        } catch {
                            SpotLogger.debug(.network, "Failed to denormalize authorIsPrivate", details: ["error": error.localizedDescription])
                        }
                        // Ensure the vibe tag exists globally (non-blocking)
                        Task { try? await VibeTagService.shared.ensureTagExists(name: vibeTag) }
                        do {
                            try await Firestore.firestore().collection("spots").document(postId).setData(data)
                            SpotLogger.info("Spot created", details: ["postId": postId])
                            completion(.success(()))
                        } catch {
                            SpotLogger.error("Create spot document failed", details: ["error": error.localizedDescription, "postId": postId])
                            // Attempt to clean up uploaded image if document creation fails
                            Task {
                                do {
                                    try await storageRef.delete()
                                    SpotLogger.info("Cleaned up orphaned image after document creation failure", details: ["postId": postId])
                                } catch {
                                    SpotLogger.debug(.network, "Failed to clean up orphaned image", details: ["postId": postId, "error": error.localizedDescription])
                                }
                            }
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }
}
