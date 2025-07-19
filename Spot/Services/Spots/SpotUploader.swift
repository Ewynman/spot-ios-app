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

    func uploadSpot(
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
                    "placeName": placeName,
                    "createdAt": FieldValue.serverTimestamp()
                ]

                Firestore.firestore().collection("spots").document(postId).setData(data) { error in
                    if let error = error {
                        SpotLogger.error("Failed to create spot document: \(error.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        SpotLogger.firebase("Spot posted successfully: \(postId)")
                        completion(.success(()))
                    }
                }
            }
        }
    }

    static func incrementUserVibeStat(userId: String, vibeTag: String) {
        let userRef = Firestore.firestore().collection("users").document(userId)
        let vibeKey = "vibeStats.\(vibeTag)"
        userRef.setData([vibeKey: FieldValue.increment(Int64(1))], merge: true)
        SpotLogger.info("Incremented vibeStats for user \(userId) and vibe \(vibeTag)")
    }
}
