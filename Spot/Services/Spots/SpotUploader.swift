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
            completion(.failure(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
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
                completion(.failure(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user data"])))
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
            completion(.failure(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
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
        storageRef.putData(imageData, metadata: nil) { _, error in
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
                    completion(.failure(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "URL not found."])))
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
                        "locationName": finalLocationName,
                        "locationName_lower": finalLocationName.lowercased(),
                        "likes": 0,
                        "saves": 0,
                        "createdAt": FieldValue.serverTimestamp()
                    ]

                    // Denormalize author's current privacy snapshot
                    Task {
                        do {
                            let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                            if let isPrivate = userDoc.data()? ["isPrivate"] as? Bool {
                                data["authorIsPrivate"] = isPrivate
                            }
                        } catch {
                            SpotLogger.warning("Failed to denormalize authorIsPrivate", details: ["error": error.localizedDescription])
                        }
                        do {
                            try await Firestore.firestore().collection("spots").document(postId).setData(data)
                            SpotLogger.info("Spot created", details: ["postId": postId])
                            completion(.success(()))
                        } catch {
                            SpotLogger.error("Create spot document failed", details: ["error": error.localizedDescription])
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }
}
