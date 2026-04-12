//
//  MapBackfillServiceLogs.swift
//  Spot
//
//  Log definitions for MapBackfillService.
//

import Foundation

enum MapBackfillServiceLogs: SpotLog {
    case backfillGeohashComplete
    case backfillGeohashFailed

    var tag: String { "MapBackfillService" }
    var level: LogLevel {
        switch self {
        case .backfillGeohashComplete: return .info
        case .backfillGeohashFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .backfillGeohashComplete: return "Backfill geohash complete"
        case .backfillGeohashFailed: return "Backfill geohash failed"
        }
    }
}
