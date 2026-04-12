//
//  LocationManagerLogs.swift
//  Spot
//
//  Log definitions for LocationManager.
//

import Foundation

enum LocationManagerLogs: SpotLog {
    case locationUpdateFailed

    var tag: String { "LocationManager" }
    var level: LogLevel {
        switch self {
        case .locationUpdateFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .locationUpdateFailed: return "Location update failed"
        }
    }
}
