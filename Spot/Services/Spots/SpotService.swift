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
            "timestamp": FieldValue.serverTimestamp()
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
