import Foundation
import os

enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case notice = "NOTICE"

    // For filtering: debug < info < warning < error < firebase
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error, .notice]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

final class SpotLogger {
    static let shared = SpotLogger()
    private init() {}

    // MARK: - Configuration
    static var minimumLevel: LogLevel = .debug // Change to .info, .warning, etc. to filter

    static func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    // MARK: - Public Logging Methods
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message: composeMessage(title: message, details: ["message": message]), file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: message, details: ["message": message]), file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message: composeMessage(title: message, details: ["message": message]), file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: message, details: ["message": message]), file: file, function: function, line: line)
    }

    static func notice(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.notice, message: composeMessage(title: message, details: ["message": message]), file: file, function: function, line: line)
    }

    // MARK: - Key/Value Structured Variants (all levels)
    static func debug(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    static func info(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    static func warning(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    static func error(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    static func notice(_ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        log(.notice, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
    }

    // MARK: - Private Logging Implementation
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.spotapp.spot", category: "SpotLogger")

    private static func log(_ level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard level >= minimumLevel else { return }
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[SpotLogger][\(level.rawValue)] [\(timestamp)] \(fileName):\(line) | \(function) | \(message)"

        // Use unified logging so each call is a distinct record with proper level filtering
        switch level {
        case .debug:
            logger.debug("\(logMessage, privacy: .public)")
        case .info:
            logger.info("\(logMessage, privacy: .public)")
        case .warning:
            logger.warning("\(logMessage, privacy: .public)")
        case .error:
            logger.error("\(logMessage, privacy: .public)")
        case .notice:
            logger.notice("\(logMessage, privacy: .public)")
        }

        // Optional: also print to Xcode console as a fallback
        #if DEBUG
        print(logMessage)
        #endif
    }

    // Structured logging helper (generic)
    static func structured(_ level: LogLevel, _ title: String, details: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        guard level >= minimumLevel else { return }
        log(level, message: composeMessage(title: title, details: details), file: file, function: function, line: line)
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
        return "\(title)\n[\n\(lines)\n]"
    }

    // MARK: - Convenience: Logs with Spot payload
    static func info(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }
    static func warning(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }
    static func error(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }
    static func debug(_ title: String, spot: Spot, details: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message: composeMessage(title: title, details: merge(details, with: spot)), file: file, function: function, line: line)
    }

    private static func merge(_ base: [String: Any], with spot: Spot) -> [String: Any] {
        var d = base
        d["spotId"] = spot.id ?? "nil"
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

// MARK: - Usage Examples
/*
 SpotLogger.debug("Post flow started")
 SpotLogger.info("User selected photo")
 SpotLogger.warning("Location permission denied")
 SpotLogger.error("Failed to upload spot")
 SpotLogger.firebase("Spot uploaded successfully")

 Output:
 [SpotLogger][DEBUG   ] [2024-01-15 14:30:25] PostFlowView.swift:45 | handleNext | User progressed from step 1 to step 2
 [SpotLogger][INFO    ] [2024-01-15 14:30:26] PhotoSelectionView.swift:23 | User selected photo from gallery
 [SpotLogger][ERROR   ] [2024-01-15 14:30:27] LocationSelectionView.swift:45 | Failed to search places: Network error
*/ 
