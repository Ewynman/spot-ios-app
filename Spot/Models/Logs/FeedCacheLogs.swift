//
//  FeedCacheLogs.swift
//  Spot
//
//  Log definitions for FeedCache.
//

import Foundation

enum FeedCacheLogs: SpotLog {
    case clearingCache
    case usingCachedFeed
    case loadingInitialFromFirebase
    case loadedAndCached
    case loadingMoreFromFirebase
    case loadedAndCachedMore

    var tag: String { "FeedCache" }
    var level: LogLevel {
        switch self {
        case .clearingCache: return .debug
        case .usingCachedFeed: return .info
        case .loadingInitialFromFirebase: return .debug
        case .loadedAndCached: return .info
        case .loadingMoreFromFirebase: return .debug
        case .loadedAndCachedMore: return .info
        }
    }
    var message: String {
        switch self {
        case .clearingCache: return "Clearing feed cache"
        case .usingCachedFeed: return "Using cached feed"
        case .loadingInitialFromFirebase: return "Loading initial feed from Firebase"
        case .loadedAndCached: return "Loaded and cached spots"
        case .loadingMoreFromFirebase: return "Loading more spots from Firebase"
        case .loadedAndCachedMore: return "Loaded and cached more spots"
        }
    }
}
