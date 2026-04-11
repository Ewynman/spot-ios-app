//
//  FreshInstallDetectorLogs.swift
//  Spot
//
//  Log definitions for FreshInstallDetector.
//

import Foundation

enum FreshInstallDetectorLogs: SpotLog {
    case reinstallWithKeychainUser
    case autoSignOutFailed
    case reinstallWithoutKeychainUser
    case clearedAllCaches

    var tag: String { "FreshInstallDetector" }
    var level: LogLevel {
        switch self {
        case .reinstallWithKeychainUser: return .info
        case .autoSignOutFailed: return .error
        case .reinstallWithoutKeychainUser: return .info
        case .clearedAllCaches: return .info
        }
    }
    var message: String {
        switch self {
        case .reinstallWithKeychainUser: return "Reinstall detected with keychain user: auto sign out"
        case .autoSignOutFailed: return "Failed to auto sign out on fresh install"
        case .reinstallWithoutKeychainUser: return "Reinstall without keychain user: no action needed"
        case .clearedAllCaches: return "Cleared all caches and session data"
        }
    }
}
