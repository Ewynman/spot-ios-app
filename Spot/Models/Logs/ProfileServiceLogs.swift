//
//  ProfileServiceLogs.swift
//  Spot
//
//  Log definitions for ProfileService.
//

import Foundation

enum ProfileServiceLogs: SpotLog {
    case fetchingProfileData

    var tag: String { "ProfileService" }
    var level: LogLevel {
        switch self {
        case .fetchingProfileData: return .debug
        }
    }
    var message: String {
        switch self {
        case .fetchingProfileData: return "Fetching profile data for user"
        }
    }
}
