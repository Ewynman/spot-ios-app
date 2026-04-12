//
//  BookmarksViewModelLogs.swift
//  Spot
//
//  Log definitions for BookmarksViewModel.
//

import Foundation

enum BookmarksViewModelLogs: SpotLog {
    case loadedSpots
    case loadInitialFailed

    var tag: String { "BookmarksViewModel" }
    var level: LogLevel {
        switch self {
        case .loadedSpots: return .info
        case .loadInitialFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .loadedSpots: return "Loaded spots for bookmarks"
        case .loadInitialFailed: return "BookmarksViewModel loadInitial failed"
        }
    }
}
