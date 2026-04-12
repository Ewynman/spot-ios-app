//
//  AnalyticsServiceLogs.swift
//  Spot
//
//  Log definitions for AnalyticsService.
//

import Foundation

enum AnalyticsServiceLogs: SpotLog {
    case eventTracked

    var tag: String { "AnalyticsService" }
    var level: LogLevel {
        switch self {
        case .eventTracked: return .debug
        }
    }
    var message: String {
        switch self {
        case .eventTracked: return "Analytics event tracked"
        }
    }
}
