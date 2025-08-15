//
//  FeedFlags.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation

/// Runtime flags to control feed behavior and diagnostics
struct FeedFlags {
    /// Disable any persistent deduplication across app sessions
    static var disablePersistentDedupe: Bool = false
    
    /// Enable comprehensive logging for feed diagnostics
    static var enableDiagnosticLogging: Bool = true
    
    /// TTL for persistent seen tracking (in hours, 0 = disabled)
    static var persistentSeenTTL: TimeInterval = 0 // 0 = disabled
    
    /// Unified page size across all feed components
    static let pageSize: Int = 24
}

/// Feed diagnostic logging
struct FeedDiagnostics {
    static func logExclusion(reason: String, source: String, spot: Spot) {
        guard FeedFlags.enableDiagnosticLogging else { return }
        
        SpotLogger.warning("Feed exclusion - reason: \(reason), source: \(source), spotId: \(spot.id ?? "nil"), createdAt: \(spot.createdAt?.description ?? "nil"), likes: \(spot.likes ?? 0), username: \(spot.username ?? "nil")")
    }
    
    static func logFeedStats(recentCount: Int, trendingCount: Int, nilIdCount: Int, excludedByPersistentSeen: Int, excludedByBlendSeen: Int, excludedByExistingIds: Int) {
        guard FeedFlags.enableDiagnosticLogging else { return }
        
        SpotLogger.info("Feed stats - recent: \(recentCount), trending: \(trendingCount), nilId: \(nilIdCount), excludedByPersistentSeen: \(excludedByPersistentSeen), excludedByBlendSeen: \(excludedByBlendSeen), excludedByExistingIds: \(excludedByExistingIds)")
    }
    
    static func logColdStart(seenSetSize: Int, isApplied: Bool) {
        guard FeedFlags.enableDiagnosticLogging else { return }
        
        SpotLogger.info("Feed cold start - seenSetSize: \(seenSetSize), isApplied: \(isApplied), disablePersistentDedupe: \(FeedFlags.disablePersistentDedupe)")
    }
}
