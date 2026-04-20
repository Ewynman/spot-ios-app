//
//  SupabaseUserServiceLogs.swift
//  Spot
//

import Foundation

enum SupabaseUserServiceLogs: SpotLog {
    case syncStarted
    case syncSucceeded
    case syncFailed

    var tag: String { "SupabaseUserService" }
    var level: LogLevel {
        switch self {
        case .syncStarted: return .debug
        case .syncSucceeded: return .info
        case .syncFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .syncStarted: return "Supabase user sync started"
        case .syncSucceeded: return "Supabase user sync succeeded"
        case .syncFailed: return "Supabase user sync failed"
        }
    }
}
