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
    let isPrivate: Bool
    let isFollowing: Bool
    let hasRequested: Bool
    let canView: Bool
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
        let targetIsPrivate = data["isPrivate"] as? Bool ?? false

        let currentUserId = Auth.auth().currentUser?.uid
        var isFollowing = false
        var hasRequested = false
        var canView = true
        if let currentUserId, currentUserId != id {
            let viewerDoc = try await Firestore.firestore().collection("users").document(currentUserId).getDocument()
            let following = viewerDoc.data()? ["following"] as? [String] ?? []
            let requested = viewerDoc.data()? ["requestedFollows"] as? [String] ?? []
            isFollowing = following.contains(id)
            hasRequested = requested.contains(id)
            canView = !targetIsPrivate || isFollowing
        }

        let spotsSnapshot: QuerySnapshot?
        if canView {
            spotsSnapshot = try await Firestore.firestore()
                .collection("spots")
                .whereField("userId", isEqualTo: id)
                .order(by: "createdAt", descending: true)
                .getDocuments()
        } else {
            spotsSnapshot = nil
        }

        let spots: [Spot] = try await {
            guard let spotsSnapshot else { return [] }
            return try await withThrowingTaskGroup(of: Spot?.self) { group in
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
        }()

        return ProfileData(
            username: username,
            profileImageURL: profileImageURL,
            isPrivate: targetIsPrivate,
            isFollowing: isFollowing,
            hasRequested: hasRequested,
            canView: currentUserId == id ? true : canView,
            spots: spots
        )
    }
}
