//
//  ConfirmNewEmailViewLogs.swift
//  Spot
//
//  Log definitions for ConfirmNewEmailView.
//

import Foundation

enum ConfirmNewEmailViewLogs: SpotLog {
    case changeEmailVerified
    case checkNowFailed
    case changeEmailVerifySent
    case resendFailed

    var tag: String { "ConfirmNewEmailView" }
    var level: LogLevel {
        switch self {
        case .changeEmailVerified: return .info
        case .checkNowFailed: return .error
        case .changeEmailVerifySent: return .info
        case .resendFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .changeEmailVerified: return "Email change verified"
        case .checkNowFailed: return "Check verification status failed"
        case .changeEmailVerifySent: return "Change email verification sent"
        case .resendFailed: return "Resend verification failed"
        }
    }
}
