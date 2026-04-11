//
//  ConfirmEmailViewLogs.swift
//  Spot
//
//  Log definitions for ConfirmEmailView.
//

import Foundation

enum ConfirmEmailViewLogs: SpotLog {
    case verificationTimeout
    case verificationEmailResent

    var tag: String { "ConfirmEmailView" }
    var level: LogLevel {
        switch self {
        case .verificationTimeout: return .debug
        case .verificationEmailResent: return .info
        }
    }
    var message: String {
        switch self {
        case .verificationTimeout: return "Email verification timeout"
        case .verificationEmailResent: return "Verification email resent"
        }
    }
}
