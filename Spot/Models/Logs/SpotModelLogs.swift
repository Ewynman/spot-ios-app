//
//  SpotModelLogs.swift
//  Spot
//
//  Log definitions for SpotModel.
//

import Foundation

enum SpotModelLogs: SpotLog {
    case geocodingFailed
    case decodeFailed

    var tag: String { "Spot" }
    var level: LogLevel {
        switch self {
        case .geocodingFailed: return .error
        case .decodeFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .geocodingFailed: return "Geocoding failed for spot"
        case .decodeFailed: return "Failed to decode spot"
        }
    }
}
