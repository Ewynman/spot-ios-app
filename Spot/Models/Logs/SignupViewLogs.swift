//
//  SignupViewLogs.swift
//  Spot
//
//  Log definitions for SignupView.
//

import Foundation

enum SignupViewLogs: SpotLog {
    case usernameBlocked
    case emailAlreadyRegistered

    var tag: String { "SignupView" }
    var level: LogLevel {
        switch self {
        case .usernameBlocked: return .debug
        case .emailAlreadyRegistered: return .info
        }
    }
    var message: String {
        switch self {
        case .usernameBlocked: return "Username blocked"
        case .emailAlreadyRegistered: return "Signup blocked: email already registered"
        }
    }
}
