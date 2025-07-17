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

    func uploadSpot(image: UIImage, caption: String, vibeTag: String, latitude: Double, longitude: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not logged in."])))
            return
        }

        // Compress the image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image conversion failed."])))
            return
        }

        let filename = UUID().uuidString
        let storageRef = Storage.storage().reference().child("spots/\(filename).jpg")

        storageRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let imageUrl = url?.absoluteString else {
                    completion(.failure(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "URL not found."])))
                    return
                }

                let data: [String: Any] = [
                    "userId": uid,
                    "imageURL": imageUrl,
                    "caption": caption,
                    "vibeTag": vibeTag,
                    "latitude": latitude,
                    "longitude": longitude,
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
        }
    }
}
