//
//  FirestoreSearchDataSourceLogs.swift
//  Spot
//
//  Log definitions for FirestoreSearchDataSource.
//

import Foundation

enum FirestoreSearchDataSourceLogs: SpotLog {
    case userSearchFallback
    case locationSuggestions
    case locationSuggestionsFallback
    case vibeSuggestions
    case vibeSuggestionsFallback
    case gridFallbackLocationName
    case gridFallbackVibeTag

    var tag: String { "FirestoreSearchDataSource" }
    var level: LogLevel {
        switch self {
        case .userSearchFallback: return .debug
        case .locationSuggestions: return .debug
        case .locationSuggestionsFallback: return .debug
        case .vibeSuggestions: return .debug
        case .vibeSuggestionsFallback: return .debug
        case .gridFallbackLocationName: return .debug
        case .gridFallbackVibeTag: return .debug
        }
    }
    var message: String {
        switch self {
        case .userSearchFallback: return "Search users: username_lower returned 0, falling back to username range"
        case .locationSuggestions: return "Location suggestions"
        case .locationSuggestionsFallback: return "Location suggestions fallback"
        case .vibeSuggestions: return "Vibe suggestions"
        case .vibeSuggestionsFallback: return "Vibe suggestions fallback"
        case .gridFallbackLocationName: return "Grid fallback: no locationName_lower matches; trying range on locationName"
        case .gridFallbackVibeTag: return "Grid fallback: no vibeTag_lower matches; trying range on vibeTag"
        }
    }
}
