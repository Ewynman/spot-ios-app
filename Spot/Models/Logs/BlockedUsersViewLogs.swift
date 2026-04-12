//
//  BlockedUsersViewLogs.swift
//  Spot
//
//  Log definitions for BlockedUsersView.
//

import Foundation

enum BlockedUsersViewLogs: SpotLog {
    case loadBlockedUserDetailsFailed
    case userUnblocked
    case unblockUserFailed

    var tag: String { "BlockedUsersView" }
    var level: LogLevel {
        switch self {
        case .loadBlockedUserDetailsFailed: return .error
        case .userUnblocked: return .info
        case .unblockUserFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .loadBlockedUserDetailsFailed: return "Failed to load blocked user details"
        case .userUnblocked: return "User unblocked from settings"
        case .unblockUserFailed: return "Failed to unblock user"
        }
    }
}
