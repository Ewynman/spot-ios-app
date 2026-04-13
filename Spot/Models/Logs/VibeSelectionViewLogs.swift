//
//  VibeSelectionViewLogs.swift
//  Spot
//
//  Log definitions for VibeSelectionView.
//

import Foundation

enum VibeSelectionViewLogs: SpotLog {
    case vibeSelected

    var tag: String { "VibeSelectionView" }
    var level: LogLevel {
        switch self {
        case .vibeSelected: return .info
        }
    }
    var message: String {
        switch self {
        case .vibeSelected: return "User selected vibe"
        }
    }
}
