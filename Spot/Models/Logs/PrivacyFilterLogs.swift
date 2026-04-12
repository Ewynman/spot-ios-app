//
//  PrivacyFilterLogs.swift
//  Spot
//
//  Log definitions for PrivacyFilter.
//

import Foundation

enum PrivacyFilterLogs: SpotLog {
    case fetchFollowingListFailed
    case fetchPrivateStatusFailed

    var tag: String { "PrivacyFilter" }
    var level: LogLevel {
        switch self {
        case .fetchFollowingListFailed: return .error
        case .fetchPrivateStatusFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .fetchFollowingListFailed: return "Failed to fetch following list"
        case .fetchPrivateStatusFailed: return "Failed to fetch private status"
        }
    }
}
