//
//  FollowNotificationRouter.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation

/// Holds the profile-tab destination for a follow notification the user tapped.
@MainActor
final class FollowNotificationRouter: ObservableObject {
    static let shared = FollowNotificationRouter()

    enum Destination: Equatable {
        case followRequests(acceptRequesterUid: String?)
        case profile(userId: String)
    }

    @Published var destination: Destination?

    private init() {}
}
