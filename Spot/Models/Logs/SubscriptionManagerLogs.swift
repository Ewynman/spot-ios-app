//
//  SubscriptionManagerLogs.swift
//  Spot
//
//  Log definitions for SubscriptionManager.
//

import Foundation

enum SubscriptionManagerLogs: SpotLog {
    case noMatchingProduct
    case ensureProductLoadedFailed
    case unhandledPurchaseResult

    var tag: String { "SubscriptionManager" }
    var level: LogLevel {
        switch self {
        case .noMatchingProduct: return .error
        case .ensureProductLoadedFailed: return .error
        case .unhandledPurchaseResult: return .error
        }
    }
    var message: String {
        switch self {
        case .noMatchingProduct: return "StoreKit: No matching product found"
        case .ensureProductLoadedFailed: return "StoreKit ensureProductLoaded failed"
        case .unhandledPurchaseResult: return "StoreKit: Unhandled Product.PurchaseResult"
        }
    }
}
