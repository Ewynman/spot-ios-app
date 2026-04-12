//
//  FeedCandidateServiceLogs.swift
//  Spot
//
//  Log definitions for FeedCandidateService.
//

import Foundation

enum FeedCandidateServiceLogs: SpotLog {
    case trendingQueryFallback

    var tag: String { "FeedCandidateService" }
    var level: LogLevel {
        switch self {
        case .trendingQueryFallback: return .debug
        }
    }
    var message: String {
        switch self {
        case .trendingQueryFallback: return "Trending query failed, falling back to createdAt desc"
        }
    }
}
