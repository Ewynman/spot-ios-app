//
//  ShareSheetLogs.swift
//  Spot
//
//  Log definitions for ShareSheet.
//

import Foundation

enum ShareSheetLogs: SpotLog {
    case imageLoadFailed
    case sharePrepared

    var tag: String { "ShareSheet" }
    var level: LogLevel {
        switch self {
        case .imageLoadFailed: return .debug
        case .sharePrepared: return .info
        }
    }
    var message: String {
        switch self {
        case .imageLoadFailed: return "Failed to load image for share preview"
        case .sharePrepared: return "Share prepared for spot"
        }
    }
}
