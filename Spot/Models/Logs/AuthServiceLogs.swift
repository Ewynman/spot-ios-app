//
//  AuthServiceLogs.swift
//  Spot
//
//  Log definitions for AuthService.
//

import Foundation

enum AuthServiceLogs: SpotLog {
    case emailInUseDetected
    case emailInUseReset
    case verifyUserExistsNoCurrentUser
    case verifyUserExistsChecking
    case verifyUserExistsError
    case missingFirestoreUserDoc
    case verificationEmailSentToNewAddress
    case deleteByEmailRequested
    case deleteAuthUserByEmailPlaceholder
    case deleteByEmailSuccess

    var tag: String { "AuthService" }
    var level: LogLevel {
        switch self {
        case .emailInUseDetected: return .info
        case .emailInUseReset: return .info
        case .verifyUserExistsNoCurrentUser: return .debug
        case .verifyUserExistsChecking: return .debug
        case .verifyUserExistsError: return .error
        case .missingFirestoreUserDoc: return .error
        case .verificationEmailSentToNewAddress: return .info
        case .deleteByEmailRequested: return .info
        case .deleteAuthUserByEmailPlaceholder: return .debug
        case .deleteByEmailSuccess: return .info
        }
    }
    var message: String {
        switch self {
        case .emailInUseDetected: return "Email already in use detected"
        case .emailInUseReset: return "Email in use flag reset"
        case .verifyUserExistsNoCurrentUser: return "verifyUserExists: no current user"
        case .verifyUserExistsChecking: return "verifyUserExists: checking user"
        case .verifyUserExistsError: return "verifyUserExists error"
        case .missingFirestoreUserDoc: return "Missing Firestore user doc, signing out"
        case .verificationEmailSentToNewAddress: return "Verification email sent to new address"
        case .deleteByEmailRequested: return "Delete auth user by email requested"
        case .deleteAuthUserByEmailPlaceholder: return "deleteAuthUserByEmail: implement Cloud Function"
        case .deleteByEmailSuccess: return "Delete auth user by email succeeded"
        }
    }
}
