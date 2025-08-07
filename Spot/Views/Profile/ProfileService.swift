//
//  ProfileService.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct ProfileData {
    let username: String
    let profileImageURL: String?
    let spots: [Spot]
}

enum ProfileService {
    static func fetchProfile(for userId: String?) async throws -> ProfileData {
        let id: String

        if let providedId = userId {
            id = providedId
        } else {
            guard let currentId = Auth.auth().currentUser?.uid else {
                throw NSError(domain: "No current user ID", code: 0)
            }
            id = currentId
        }

        SpotLogger.debug("Fetching profile data for userId: \(id)")

        let userDoc = try await Firestore.firestore()
            .collection("users")
            .document(id)
            .getDocument()

        guard let data = userDoc.data() else {
            throw NSError(domain: "User not found", code: 0)
        }

        let username = data["username"] as? String ?? "User"
        let profileImageURL = data["profileImageURL"] as? String

        let spotsSnapshot = try await Firestore.firestore()
            .collection("spots")
            .whereField("userId", isEqualTo: id)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let spots = try await withThrowingTaskGroup(of: Spot?.self) { group in
            for document in spotsSnapshot.documents {
                group.addTask {
                    return try await Spot.fromDocument(document)
                }
            }

            var validSpots: [Spot] = []
            for try await spot in group {
                if let spot = spot {
                    validSpots.append(spot)
                }
            }
            return validSpots
        }

        return ProfileData(username: username, profileImageURL: profileImageURL, spots: spots)
    }
}
