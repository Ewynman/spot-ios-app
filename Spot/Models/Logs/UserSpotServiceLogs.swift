//
//  UserSpotServiceLogs.swift
//  Spot
//
//  Log definitions for UserSpotService.
//

import Foundation

enum UserSpotServiceLogs: SpotLog {
    case noUserIdAvailable
    case fetchingLikedSpots
    case foundLikedSpotIds
    case noLikedSpotsFound
    case fetchSpotFailed

    var tag: String { "UserSpotService" }
    var level: LogLevel {
        switch self {
        case .noUserIdAvailable: return .error
        case .fetchingLikedSpots: return .info
        case .foundLikedSpotIds: return .info
        case .noLikedSpotsFound: return .info
        case .fetchSpotFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .noUserIdAvailable: return "No user ID available"
        case .fetchingLikedSpots: return "Fetching liked spots for user"
        case .foundLikedSpotIds: return "Found liked spot IDs"
        case .noLikedSpotsFound: return "No liked spots found"
        case .fetchSpotFailed: return "Failed to fetch spot"
        }
    }
}
