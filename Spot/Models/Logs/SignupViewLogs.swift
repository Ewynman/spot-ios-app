//
//  SignupViewLogs.swift
//  Spot
//
//  Log definitions for SignupView.
//

import Foundation

enum SignupViewLogs: SpotLog {
    case usernameBlocked

    var tag: String { "SignupView" }
    var level: LogLevel {
        switch self {
        case .usernameBlocked: return .debug
        }
    }
    var message: String {
        switch self {
        case .usernameBlocked: return "Username blocked"
        }
    }
}
