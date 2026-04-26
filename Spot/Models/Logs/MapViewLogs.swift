//
//  MapViewLogs.swift
//  Spot
//
//  Log definitions for MapView (discovery map) and the shared map screen
//  lifecycle. Covers map appear/disappear, panel open/close + height
//  clamping, recenter taps, and entry/initial-fit instrumentation.
//

import Foundation

enum MapViewLogs: SpotLog {
    case mapAppeared
    case mapDisappeared
    case initialFitApplied
    case homeSheetOpen
    case homeSheetClose
    case panelHeightClamped
    case recenterTapped
    case userLocationUnavailable
    case mapTabLocationRequestStarted
    case waitingForUserLocation
    case densityModeChanged
    case visibleSpotsTrimmed

    var tag: String { "MapView" }
    var level: LogLevel {
        switch self {
        case .mapAppeared: return .info
        case .mapDisappeared: return .info
        case .initialFitApplied: return .debug
        case .homeSheetOpen: return .info
        case .homeSheetClose: return .info
        case .panelHeightClamped: return .debug
        case .recenterTapped: return .info
        case .userLocationUnavailable: return .info
        case .mapTabLocationRequestStarted: return .info
        case .waitingForUserLocation: return .info
        case .densityModeChanged: return .debug
        case .visibleSpotsTrimmed: return .debug
        }
    }
    var message: String {
        switch self {
        case .mapAppeared: return "Map appeared"
        case .mapDisappeared: return "Map disappeared"
        case .initialFitApplied: return "Map initial fit applied"
        case .homeSheetOpen: return "Map home sheet opened"
        case .homeSheetClose: return "Map home sheet closed"
        case .panelHeightClamped: return "Map preview panel height clamped to safe area"
        case .recenterTapped: return "Map recenter button tapped"
        case .userLocationUnavailable: return "Map user location unavailable"
        case .mapTabLocationRequestStarted: return "Map tab requested user location"
        case .waitingForUserLocation: return "Map waiting for user location before viewport fetch"
        case .densityModeChanged: return "Map density mode changed"
        case .visibleSpotsTrimmed: return "Map visibleSpots trimmed to viewport cap"
        }
    }
}
