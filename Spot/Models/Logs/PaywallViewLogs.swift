//
//  PaywallViewLogs.swift
//  Spot
//
//  Log definitions for PaywallView.
//

import Foundation

enum PaywallViewLogs: SpotLog {
    case purchaseStarted
    case purchasePending
    case purchaseFailed
    case restoreFailed

    var tag: String { "PaywallView" }
    var level: LogLevel {
        switch self {
        case .purchaseStarted: return .info
        case .purchasePending: return .info
        case .purchaseFailed: return .error
        case .restoreFailed: return .error
        }
    }
    var message: String {
        switch self {
        case .purchaseStarted: return "User started App Store purchase"
        case .purchasePending: return "Purchase pending"
        case .purchaseFailed: return "Purchase failed"
        case .restoreFailed: return "Restore failed"
        }
    }
}
