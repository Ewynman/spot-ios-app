//
//  ProfileServiceLogs.swift
//  Spot
//
//  Log definitions for ProfileService.
//

import Foundation

enum ProfileServiceLogs: SpotLog {
    case fetchingProfileData
    case followStateQueryFailed
    case pendingFollowRequestQueryFailed

    var tag: String { "ProfileService" }
    var level: LogLevel {
        switch self {
        case .fetchingProfileData: return .debug
        case .followStateQueryFailed: return .error
        case .pendingFollowRequestQueryFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .fetchingProfileData: return "Fetching profile data for user"
        case .followStateQueryFailed: return "Follow edge query failed when loading profile"
        case .pendingFollowRequestQueryFailed: return "Pending follow request query failed when loading profile"
        }
    }
}
