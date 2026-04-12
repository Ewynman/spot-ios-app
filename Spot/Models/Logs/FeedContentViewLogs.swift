//
//  FeedContentViewLogs.swift
//  Spot
//
//  Log definitions for FeedContentView.
//

import Foundation

enum FeedContentViewLogs: SpotLog {
    case missingImageUrl

    var tag: String { "FeedContentView" }
    var level: LogLevel {
        switch self {
        case .missingImageUrl: return .error
        }
    }
    var message: String {
        switch self {
        case .missingImageUrl: return "Feed missing imageURL for spot"
        }
    }
}
