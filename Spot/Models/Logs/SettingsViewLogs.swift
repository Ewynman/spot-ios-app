//
//  SettingsViewLogs.swift
//  Spot
//
//  Log definitions for SettingsView.
//

import Foundation

enum SettingsViewLogs: SpotLog {
    case loadProfileFailed
    case usernameBlocked
    case verifyBeforeUpdateEmailFailed
    case saveFailed
    case saveSuccess
    case profilePhotoUploadStart
    case profilePhotoUploadNoUser
    case profilePhotoUpdateFirestoreFailed
    case profilePhotoUpdated
    case profilePhotoUploadFailed

    var tag: String { "SettingsView" }
    var level: LogLevel {
        switch self {
        case .loadProfileFailed: return .error
        case .usernameBlocked: return .debug
        case .verifyBeforeUpdateEmailFailed: return .error
        case .saveFailed: return .error
        case .saveSuccess: return .info
        case .profilePhotoUploadStart: return .info
        case .profilePhotoUploadNoUser: return .error
        case .profilePhotoUpdateFirestoreFailed: return .error
        case .profilePhotoUpdated: return .info
        case .profilePhotoUploadFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .loadProfileFailed: return "Settings load profile failed"
        case .usernameBlocked: return "Username blocked"
        case .verifyBeforeUpdateEmailFailed: return "Settings verify before update email failed"
        case .saveFailed: return "Settings save failed"
        case .saveSuccess: return "Settings save success"
        case .profilePhotoUploadStart: return "Profile photo upload start"
        case .profilePhotoUploadNoUser: return "Profile photo upload: no user"
        case .profilePhotoUpdateFirestoreFailed: return "Profile photo Firestore update failed"
        case .profilePhotoUpdated: return "Profile photo updated"
        case .profilePhotoUploadFailed: return "Profile photo upload failed"
        }
    }
}
