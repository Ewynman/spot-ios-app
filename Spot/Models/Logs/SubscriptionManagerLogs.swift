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
    case transactionUpdateUnverified
    case transactionUpdateVerifiedProFinishing
    case transactionUpdateFinishingNonPro

    var tag: String { "SubscriptionManager" }
    var level: LogLevel {
        switch self {
        case .noMatchingProduct: return .error
        case .ensureProductLoadedFailed: return .error
        case .unhandledPurchaseResult: return .error
        case .transactionUpdateUnverified: return .error
        case .transactionUpdateVerifiedProFinishing: return .info
        case .transactionUpdateFinishingNonPro: return .debug
        }
    }
    var message: String {
        switch self {
        case .noMatchingProduct: return "StoreKit: No matching product found"
        case .ensureProductLoadedFailed: return "StoreKit ensureProductLoaded failed"
        case .unhandledPurchaseResult: return "StoreKit: Unhandled Product.PurchaseResult"
        case .transactionUpdateUnverified:
            return "StoreKit: Unverified transaction in Transaction.updates"
        case .transactionUpdateVerifiedProFinishing:
            return "StoreKit: Verified Pro transaction in updates; finishing"
        case .transactionUpdateFinishingNonPro:
            return "StoreKit: Finishing transaction in updates (non-Pro product)"
        }
    }
}
