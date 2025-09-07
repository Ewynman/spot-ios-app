import Foundation
import os

enum LogLevel: String, CaseIterable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case firebase = "FIREBASE"

    // For filtering: debug < info < warning < error < firebase
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error, .firebase]
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
        log(.debug, message: message, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: message, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message: message, file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: message, file: file, function: function, line: line)
    }

    static func firebase(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.firebase, message: message, file: file, function: function, line: line)
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
        case .firebase:
            logger.notice("\(logMessage, privacy: .public)")
        }

        // Optional: also print to Xcode console as a fallback
        #if DEBUG
        print(logMessage)
        #endif
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
