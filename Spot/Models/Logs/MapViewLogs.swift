//
//  MapViewLogs.swift
//  Spot
//
//  Log definitions for MapView.
//

import Foundation

enum MapViewLogs: SpotLog {
    case homeSheetClose

    var tag: String { "MapView" }
    var level: LogLevel {
        switch self {
        case .homeSheetClose: return .info
        }
    }
    var message: String {
        switch self {
        case .homeSheetClose: return "Map home sheet closed"
        }
    }
}
