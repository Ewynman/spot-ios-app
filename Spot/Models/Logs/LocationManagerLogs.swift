//
//  LocationManagerLogs.swift
//  Spot
//
//  Log definitions for LocationManager.
//

import Foundation

enum LocationManagerLogs: SpotLog {
    case locationUpdateFailed
    case locationFixReceived
    case authorizationChanged
    case authorizationRequested
    case oneShotLocationRequested
    case startUpdatingLocation
    case stopUpdatingLocation
    case simulatorOverrideApplied

    var tag: String { "LocationManager" }
    var level: LogLevel {
        switch self {
        case .locationUpdateFailed: return .error
        case .authorizationChanged, .authorizationRequested,
             .oneShotLocationRequested, .startUpdatingLocation, .stopUpdatingLocation,
             .simulatorOverrideApplied:
            return .info
        case .locationFixReceived: return .debug
        }
    }
    var message: String {
        switch self {
        case .locationUpdateFailed: return "Location update failed"
        case .locationFixReceived: return "Received location fix"
        case .authorizationChanged: return "Location authorization changed"
        case .authorizationRequested: return "Requested location authorization"
        case .oneShotLocationRequested: return "Requested one-shot location fix"
        case .startUpdatingLocation: return "startUpdatingLocation called"
        case .stopUpdatingLocation: return "stopUpdatingLocation called"
        case .simulatorOverrideApplied: return "Simulator location override applied"
        }
    }
}
