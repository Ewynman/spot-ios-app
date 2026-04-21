//
//  LoggingConfig.swift
//  Spot
//
//  Created for centralized logging configuration
//

import Foundation

/// Centralized logging configuration
/// Use this to enable/disable debug categories at app startup
struct LoggingConfig {
    /// Configure debug logging categories
    /// Call this in AppDelegate or App init to control what debug logs are enabled
    static func configure() {
        // Default: All debug categories disabled for production
        // Enable specific categories as needed for debugging
        
        // Example: Enable UI and Navigation debug logs
        // DebugCategory.enable(.ui)
        // DebugCategory.enable(.navigation)
        
        // Example: Enable all debug logs (use sparingly)
        // DebugCategory.enableAll()
        
        // Example: Enable only feed debugging
        // DebugCategory.enable(.feed)
        
        // Set minimum log level (info = show info + error, debug = show all if categories enabled)
        SpotLogger.setMinimumLevel(.info)
    }
    
    // MARK: - Category-Based Presets (Simple)
    
    static func enableUILogging() {
        DebugCategory.enable(.ui)
        DebugCategory.enable(.navigation)
    }
     
    static func enableFeedLogging() {
        DebugCategory.enable(.feed)
        FeedFlags.enableDiagnosticLogging = true
    }
    
    static func enableNetworkLogging() {
        DebugCategory.enable(.network)
    }
    
    static func enableImageLogging() {
        DebugCategory.enable(.image)
    }
    
    static func enableAllDebugLogging() {
        DebugCategory.enableAll()
        SpotLogger.enableAllDebug = true
        FeedFlags.enableDiagnosticLogging = true
    }
    
    // MARK: - Component-Specific Presets (Includes component flags)
    
    static func enableSpotCardLogging() {
        ComponentLogging.spotCard = true
        DebugCategory.enable(.ui)
        DebugCategory.enable(.image)
    }
    
    static func enablePrivacyLogging() {
        ComponentLogging.authorPrivacyCache = true
        DebugCategory.enable(.privacy)
    }
    
    static func enableFeedComponentLogging() {
        ComponentLogging.feedRepository = true
        ComponentLogging.feedRanker = true
        DebugCategory.enable(.feed)
        FeedFlags.enableDiagnosticLogging = true
    }
    
    static func enablePostFlowLogging() {
        ComponentLogging.postFlow = true
        ComponentLogging.locationSelection = true
        ComponentLogging.photoSelection = true
        DebugCategory.enable(.moderation)
        DebugCategory.enable(.location)
    }
    
    static func enableAuthLogging() {
        ComponentLogging.authService = true
        ComponentLogging.authViewModel = true
        DebugCategory.enable(.auth)
    }
    
    static func enableNetworkComponentLogging() {
        ComponentLogging.spotService = true
        ComponentLogging.imageService = true
        DebugCategory.enable(.network)
        DebugCategory.enable(.image)
    }
    
    static func enableDeepLinkLogging() {
        ComponentLogging.deepLinkRouter = true
        DebugCategory.enable(.deepLink)
    }
}
