//
//  SpotService.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class SpotService {
    static let shared = SpotService()
    private init() {}

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
    
    func fetchSpotsForMap(completion: @escaping (Result<[Spot], Error>) -> Void) {
        SpotLogger.debug("Running fetchSpotsForMap query with order by 'createdAt'")
        Firestore.firestore().collection("spots")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    SpotLogger.error("fetchSpotsForMap error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    SpotLogger.warning("fetchSpotsForMap: No documents returned")
                    completion(.success([]))
                    return
                }
                
                let spots = documents.compactMap { document -> Spot? in
                    let data = document.data()
                    SpotLogger.debug("Parsing spot doc id: \(document.documentID)")
                    guard let userId = data["userId"] as? String,
                          let imageURL = data["imageURL"] as? String,
                          let latitude = data["latitude"] as? Double,
                          let longitude = data["longitude"] as? Double else {
                        SpotLogger.warning("Skipping doc id \(document.documentID) due to missing fields")
                        return nil
                    }
                    return Spot(
                        id: document.documentID,
                        userId: userId,
                        username: data["username"] as? String ?? "Unknown",
                        userProfileImageURL: data["userProfileImageURL"] as? String,
                        imageURL: imageURL,
                        caption: data["caption"] as? String,
                        vibeTag: data["vibeTag"] as? String ?? "",
                        latitude: latitude,
                        longitude: longitude,
                        locationName: data["locationName"] as? String,
                        likes: data["likes"] as? Int ?? 0,
                        isLiked: data["isLiked"] as? Bool ?? false,
                        isSaved: data["isSaved"] as? Bool ?? false,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
                    )
                }
                SpotLogger.info("fetchSpotsForMap: Parsed \(spots.count) spots")
                completion(.success(spots))
            }
    }
}
