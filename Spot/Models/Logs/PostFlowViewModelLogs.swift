//
//  PostFlowViewModelLogs.swift
//  Spot
//
//  Log definitions for PostFlowViewModel.
//

import Foundation

enum PostFlowViewModelLogs: SpotLog {
    case userWentBack
    case userProgressed
    case userCompletedPostFlow
    case postData
    case spotUploadFailed
    case moderationCheckBegin
    case moderationCheckTimeout
    case moderationGateError
    case moderationCheckApproved
    case postBlockedByModeration
    case moderationCheckRejected
    case moderationCheckPending

    var tag: String { "PostFlowViewModel" }
    var level: LogLevel {
        switch self {
        case .userWentBack: return .debug
        case .userProgressed: return .debug
        case .userCompletedPostFlow: return .info
        case .postData: return .debug
        case .spotUploadFailed: return .error
        case .moderationCheckBegin: return .info
        case .moderationCheckTimeout: return .error
        case .moderationGateError: return .error
        case .moderationCheckApproved: return .info
        case .postBlockedByModeration: return .error
        case .moderationCheckRejected: return .error
        case .moderationCheckPending: return .debug
        }
    }
    var message: String {
        switch self {
        case .userWentBack: return "User went back to previous step"
        case .userProgressed: return "User progressed to next step"
        case .userCompletedPostFlow: return "User completed post flow"
        case .postData: return "Post data summary"
        case .spotUploadFailed: return "Spot upload failed"
        case .moderationCheckBegin: return "Moderation check begin"
        case .moderationCheckTimeout: return "Moderation check timeout"
        case .moderationGateError: return "Moderation gate error"
        case .moderationCheckApproved: return "Moderation check approved"
        case .postBlockedByModeration: return "Post blocked by moderation"
        case .moderationCheckRejected: return "Moderation check rejected"
        case .moderationCheckPending: return "Moderation check pending"
        }
    }
}
