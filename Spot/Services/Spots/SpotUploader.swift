//
//  SpotUploader.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit

final class SpotUploader {
    static let shared = SpotUploader()
    private init() {}
    
    static func incrementUserVibeStat(userId: String, vibeTag: String) {
        SpotLogger.debug("Incrementing vibe stat for user \(userId) - vibe: \(vibeTag)")
        let userRef = Firestore.firestore().collection("users").document(userId)
        
        userRef.getDocument { snapshot, error in
            if let error = error {
                SpotLogger.error("Failed to get user doc for vibe stats: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data() else {
                SpotLogger.error("No user data found for vibe stats")
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
                    SpotLogger.error("Failed to update vibe stats: \(error.localizedDescription)")
                } else {
                    SpotLogger.info("Updated vibe stats for user \(userId) - \(vibeTag): \(vibeStats[vibeTag] ?? 1)")
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
                SpotLogger.error("Failed to fetch user data: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data(),
                  let username = data["username"] as? String else {
                SpotLogger.error("Invalid user data format")
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
            SpotLogger.error("User not authenticated for spot upload")
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
                SpotLogger.error("Failed to get user data: \(error.localizedDescription)")
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
            SpotLogger.error("Image conversion failed for spot upload")
            return
        }

        let postId = UUID().uuidString
        let filename = "spot_\(postId).jpg"
        let storageRef = Storage.storage().reference().child("spots/\(filename)")

        SpotLogger.info("Uploading spot image to Firebase Storage...")
        storageRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                SpotLogger.error("Failed to upload spot image: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    SpotLogger.error("Failed to get download URL: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let imageUrl = url?.absoluteString else {
                    SpotLogger.error("Download URL is nil after image upload")
                    completion(.failure(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "URL not found."])))
                    return
                }

                SpotLogger.info("Image uploaded, creating spot document in Firestore...")
                let data: [String: Any] = [
                    "postId": postId,
                    "userId": userId,
                    "username": username,
                    "userProfileImageURL": userProfileImageURL ?? "",
                    "imageURL": imageUrl,
                    "caption": "",
                    "vibeTag": vibeTag,
                    "latitude": latitude,
                    "longitude": longitude,
                    "locationName": placeName,
                    "likes": 0,
                    "saves": 0,
                    "createdAt": FieldValue.serverTimestamp()
                ]

                Firestore.firestore().collection("spots").document(postId).setData(data) { error in
                    if let error = error {
                        SpotLogger.error("Failed to create spot document: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        SpotLogger.info("Spot created successfully!")
                        completion(.success(()))
                    }
                }
            }
        }
    }
}
