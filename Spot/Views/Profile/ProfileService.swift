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
    let isPro: Bool
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

        SpotLogger.log(ProfileServiceLogs.fetchingProfileData, details: ["userId": id])

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
        
        // Check proUntil timestamp (new method) or fallback to isPro boolean (backward compatibility)
        var proUntilDate: Date? = nil
        if let timestamp = data["proUntil"] as? Timestamp {
            proUntilDate = timestamp.dateValue()
        } else if let timestamp = data["proUntil"] as? Date {
            proUntilDate = timestamp
        }
        
        // Compute isPro from proUntil (if date exists and is in future) or fallback to isPro boolean
        let targetIsPro: Bool
        if let proUntil = proUntilDate {
            targetIsPro = proUntil > Date()
        } else {
            // Backward compatibility: check isPro boolean
            targetIsPro = data["isPro"] as? Bool ?? false
        }

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
                // Ensure newest-first descending order (createdAt desc; tie-break by id)
                return validSpots.sorted { lhs, rhs in
                    let l = lhs.createdAt ?? .distantPast
                    let r = rhs.createdAt ?? .distantPast
                    if l != r { return l > r }
                    return (lhs.id ?? "") > (rhs.id ?? "")
                }
            }
        }()

        return ProfileData(
            username: username,
            profileImageURL: profileImageURL,
            isPrivate: targetIsPrivate,
            isPro: targetIsPro,
            isFollowing: isFollowing,
            hasRequested: hasRequested,
            canView: currentUserId == id ? true : canView,
            spots: spots
        )
    }
}
