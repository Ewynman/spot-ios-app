//
//  SpotPublishCoordinatorLogs.swift
//  Spot
//
//  Log definitions for SpotPublishCoordinator.
//

import Foundation

enum SpotPublishCoordinatorLogs: SpotLog {
    case imageDecodeFailed
    case spotUploadFailed
    case spotPublished

    var tag: String { "SpotPublishCoordinator" }

    var level: LogLevel {
        switch self {
        case .imageDecodeFailed, .spotUploadFailed:
            return .error
        case .spotPublished:
            return .info
        }
    }

    var message: String {
        switch self {
        case .imageDecodeFailed:
            return "Publish pipeline: could not decode JPEG drafts to images"
        case .spotUploadFailed:
            return "Publish pipeline: spot publish failed"
        case .spotPublished:
            return "Publish pipeline: spot published to Supabase"
        }
    }
}
