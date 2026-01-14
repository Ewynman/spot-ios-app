import Foundation
import os

enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"

    // For filtering: debug < info < error
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Debug log categories for fine-grained control
enum DebugCategory: String, CaseIterable {
    case ui = "UI"                    // UI interactions (taps, appears, etc.)
    case navigation = "Navigation"   // Navigation events
    case feed = "Feed"               // Feed loading, ranking, blending
    case network = "Network"         // API calls, Firestore operations
    case auth = "Auth"               // Authentication events
    case image = "Image"             // Image loading, caching
    case location = "Location"       // Location services
    case performance = "Performance" // Performance metrics
    case deepLink = "DeepLink"       // Deep linking
    case moderation = "Moderation"   // Content moderation
    case privacy = "Privacy"         // Privacy filtering
    
    static var enabledCategories: Set<DebugCategory> = []
    
    static func enable(_ category: DebugCategory) {
        enabledCategories.insert(category)
    }
    
    static func disable(_ category: DebugCategory) {
        enabledCategories.remove(category)
    }
    
    static func enableAll() {
        enabledCategories = Set(DebugCategory.allCases)
    }
    
    static func disableAll() {
        enabledCategories.removeAll()
    }
    
    var isEnabled: Bool {
        return DebugCategory.enabledCategories.contains(self)
    }
}

/// Component-specific logging flags for major files/components
struct ComponentLogging {
    // UI Components
    static var spotCard: Bool = false
    static var profileView: Bool = false
    static var searchView: Bool = false
    static var feedView: Bool = false
    
    // Services
    static var authorPrivacyCache: Bool = false
    static var feedRepository: Bool = false
    static var feedRanker: Bool = false
    static var spotService: Bool = false
    static var spotUploader: Bool = false
    static var authService: Bool = false
    static var imageService: Bool = false
    static var deepLinkRouter: Bool = false
    
    // ViewModels
    static var authViewModel: Bool = false
    static var likesViewModel: Bool = false
    static var bookmarksViewModel: Bool = false
    
    // Post Flow
    static var postFlow: Bool = false
    static var locationSelection: Bool = false
    static var photoSelection: Bool = false
}

final class SpotLogger {
    static let shared = SpotLogger()
    private init() {}

    // MARK: - Configuration
    static var minimumLevel: LogLevel = .info // Default to info, debug requires category enablement
    static var enableAllDebug: Bool = false   // Master switch for all debug logs

    static func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    // MARK: - Public Logging Methods
    
    // INFO - Always enabled for important events
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: "", details: ["message": message]), file: file, function: function, line: line)
    }

    static func info(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    // ERROR - Always enabled
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: "", details: ["message": message]), file: file, function: function, line: line)
    }

    static func error(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    // DEBUG - Category-based, requires explicit enablement
    static func debug(_ category: DebugCategory, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLogDebug(category: category, file: file) else { return }
        log(.debug, message: composeMessage(title: "", details: ["category": category.rawValue, "message": message]), file: file, function: function, line: line)
    }

    static func debug(_ category: DebugCategory, _ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLogDebug(category: category, file: file) else { return }
        var enhancedDetails = details
        enhancedDetails["category"] = category.rawValue
        log(.debug, message: composeMessage(title: title, details: enhancedDetails), file: file, function: function, line: line)
    }

    // Convenience debug methods (backward compatibility - defaults to UI category)
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        debug(.ui, message, file: file, function: function, line: line)
    }

    static func debug(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        debug(.ui, title, details: details, file: file, function: function, line: line)
    }

    // MARK: - Private Logging Implementation
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.spotapp.spot", category: "SpotLogger")

    private static func shouldLogDebug(category: DebugCategory, file: String) -> Bool {
        // Always log if master switch is on
        if enableAllDebug { return true }
        // Check component-specific flag
        if isComponentEnabled(file: file) { return true }
        // Log if category is enabled
        return category.isEnabled
    }
    
    private static func isComponentEnabled(file: String) -> Bool {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        switch fileName {
        case "SpotCard.swift": return ComponentLogging.spotCard
        case "ProfileView.swift": return ComponentLogging.profileView
        case "SearchView.swift": return ComponentLogging.searchView
        case "HomepageView.swift", "FeedView.swift": return ComponentLogging.feedView
        case "AuthorPrivacyCache.swift": return ComponentLogging.authorPrivacyCache
        case "FeedRepository.swift": return ComponentLogging.feedRepository
        case "FeedRanker.swift": return ComponentLogging.feedRanker
        case "SpotService.swift": return ComponentLogging.spotService
        case "SpotUploader.swift": return ComponentLogging.spotUploader
        case "AuthService.swift": return ComponentLogging.authService
        case "ImageService.swift": return ComponentLogging.imageService
        case "DeepLinkRouter.swift": return ComponentLogging.deepLinkRouter
        case "AuthViewModel.swift": return ComponentLogging.authViewModel
        case "LikesViewModel.swift": return ComponentLogging.likesViewModel
        case "BookmarksViewModel.swift": return ComponentLogging.bookmarksViewModel
        case "PostFlowView.swift": return ComponentLogging.postFlow
        case "LocationSelectionView.swift": return ComponentLogging.locationSelection
        case "PhotoSelectionView.swift": return ComponentLogging.photoSelection
        default: return false
        }
    }

    private static func log(_ level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard level >= minimumLevel else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[SpotLogger][\(level.rawValue)] \(fileName):\(line) | \(function) | \(message)"

        // Use unified logging so each call is a distinct record with proper level filtering
        switch level {
        case .debug:
            logger.debug("\(logMessage, privacy: .public)")
        case .info:
            logger.info("\(logMessage, privacy: .public)")
        case .error:
            logger.error("\(logMessage, privacy: .public)")
        }

        // Optional: also print to Xcode console as a fallback
        #if DEBUG
        print(logMessage)
        #endif
    }

    // MARK: - Compose message with JSON details
    private static func composeMessage(title: String, details: [String: Any]) -> String {
        // Pretty multi-line details block
        let lines = details
            .map { key, value in
                let v: String
                if let date = value as? Date {
                    v = date.description
                } else if let arr = value as? [Any] {
                    v = arr.map { String(describing: $0) }.joined(separator: ", ")
                } else {
                    v = String(describing: value)
                }
                return "     \(key): \(v)"
            }
            .sorted()
            .joined(separator: "\n")
        
        // If title is empty, only show details block
        if title.isEmpty {
            return "[\n\(lines)\n]"
        }
        return "\(title)\n[\n\(lines)\n]"
    }

    // MARK: - Convenience: Logs with Spot payload
    static func info(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }
    
    static func error(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }
    
    static func debug(_ category: DebugCategory, _ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLogDebug(category: category, file: file) else { return }
        log(.debug, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }

    private static func merge(_ base: [String: Any], with spot: Spot) -> [String: Any] {
        var d = base
        d["spotId"] = spot.safeId
        d["userId"] = spot.userId ?? "nil"
        d["username"] = spot.username ?? "nil"
        d["likes"] = spot.likes ?? 0
        d["createdAt"] = spot.createdAt ?? Date.distantPast
        d["imageURL"] = spot.imageURL ?? "nil"
        d["thumbnailURL"] = spot.thumbnailURL ?? "nil"
        d["locationName"] = spot.locationName ?? "nil"
        return d
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
