//
//  TokenServiceLogs.swift
//  Spot
//
//  Log definitions for TokenService.
//

import Foundation

enum TokenServiceLogs: SpotLog {
    case usingCachedToken
    case forcingTokenRefresh
    case clearedStoredTokens
    case noAuthenticatedUser
    case failedToGetIdToken
    case noTokenReceived
    case gotFreshToken
    case failedToSaveToKeychain

    var tag: String { "TokenService" }
    var level: LogLevel {
        switch self {
        case .usingCachedToken: return .debug
        case .forcingTokenRefresh: return .debug
        case .clearedStoredTokens: return .debug
        case .noAuthenticatedUser: return .error
        case .failedToGetIdToken: return .error
        case .noTokenReceived: return .error
        case .gotFreshToken: return .debug
        case .failedToSaveToKeychain: return .error
        }
    }
    var message: String {
        switch self {
        case .usingCachedToken: return "Using cached token"
        case .forcingTokenRefresh: return "Forcing token refresh"
        case .clearedStoredTokens: return "Cleared stored tokens"
        case .noAuthenticatedUser: return "No authenticated user"
        case .failedToGetIdToken: return "Failed to get ID token"
        case .noTokenReceived: return "No token received from Firebase"
        case .gotFreshToken: return "Got fresh token from Firebase"
        case .failedToSaveToKeychain: return "Failed to save to keychain"
        }
    }
}
