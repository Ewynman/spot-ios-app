//
//  MapViewModelLogs.swift
//  Spot
//
//  Log definitions for MapViewModel.
//

import Foundation

enum MapViewModelLogs: SpotLog {
    case mapLoadedAllSpots
    case loadAllSpotsFailed

    var tag: String { "MapViewModel" }
    var level: LogLevel {
        switch self {
        case .mapLoadedAllSpots: return .info
        case .loadAllSpotsFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .mapLoadedAllSpots: return "Map loaded all spots"
        case .loadAllSpotsFailed: return "Failed to load all spots for map"
        }
    }
}
