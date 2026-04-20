import Foundation
import StoreKit
import UIKit

/// Thrown when StoreKit returns a `Product.PurchaseResult` case this app was not built to handle (e.g. new API in a future OS).
enum SubscriptionPurchaseError: LocalizedError {
    case unknownPurchaseOutcome

    var errorDescription: String? {
        switch self {
        case .unknownPurchaseOutcome:
            return "Unexpected purchase result from the App Store. Update Spot or try again, and contact support if it continues."
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    private init() {}

    @Published var isPurchasing: Bool = false
    @Published var isRestoring: Bool = false
    @Published var hasProduct: Bool = false

    // Try current and legacy IDs to avoid config mismatches during setup
    let productIds: [String] = ["spotPro", "spot.pro.yearly"]

    private var cachedProduct: Product?
    private var transactionUpdatesTask: Task<Void, Never>?

    func loadProduct() async throws -> Product {
        if let p = cachedProduct { return p }
        let products = try await Product.products(for: productIds)
        guard let product = products.first else {
            SpotLogger.log(SubscriptionManagerLogs.noMatchingProduct, details: ["ids": productIds])
            throw NSError(domain: "StoreKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No products found. Select a .storekit file in Scheme > Run > Options or finish subscription setup in App Store Connect."])
        }
        cachedProduct = product
        hasProduct = true
        return product
    }

    func ensureProductLoaded() async {
        if cachedProduct != nil { hasProduct = true; return }
        do {
            _ = try await loadProduct()
        } catch {
            hasProduct = false
            SpotLogger.log(SubscriptionManagerLogs.ensureProductLoadedFailed, details: ["error": error.localizedDescription])
        }
    }

    enum PurchaseProResult: Sendable {
        case purchased(expirationDate: Date?)
        case pending
        case userCancelled
    }

    /// Starts the App Store purchase flow. Returns whether a verified purchase completed on-device.
    func purchasePro() async throws -> PurchaseProResult {
        isPurchasing = true
        defer { isPurchasing = false }
        let product = try await loadProduct()
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            let expirationDate = transaction.expirationDate
            await transaction.finish()
            return .purchased(expirationDate: expirationDate)
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            SpotLogger.log(SubscriptionManagerLogs.unhandledPurchaseResult, details: ["hint": "Future StoreKit may add cases; update SubscriptionManager.purchasePro"])
            throw SubscriptionPurchaseError.unknownPurchaseOutcome
        }
    }

    func restorePurchases() async throws {
        isRestoring = true
        defer { isRestoring = false }
        try await AppStore.sync()
    }

    /// Start listening for StoreKit transaction updates for the app lifetime.
    /// This avoids missing successful purchases that complete outside the immediate purchase flow.
    func startTransactionUpdatesListener(
        onEntitlementChanged: (@Sendable (Bool, Date?) async -> Void)? = nil
    ) {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task.detached(priority: .background) { [productIds] in
            let checker = ProEntitlementChecker(proProductIDs: productIds)
            for await update in Transaction.updates {
                do {
                    let transaction = try await Self.checkVerifiedStatic(update)
                    defer { Task { await transaction.finish() } }

                    guard checker.grantsPro(forProductID: transaction.productID) else { continue }
                    await onEntitlementChanged?(true, transaction.expirationDate)
                } catch {
                    continue
                }
            }
        }
    }

    func refreshEntitlement() async -> Bool {
        let checker = ProEntitlementChecker(proProductIDs: productIds)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               checker.grantsPro(forProductID: transaction.productID) {
                return true
            }
        }
        return false
    }

    /// Returns the expiration date of the active Pro entitlement, or nil if not subscribed.
    func refreshEntitlementExpiry() async -> Date? {
        let checker = ProEntitlementChecker(proProductIDs: productIds)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               checker.grantsPro(forProductID: transaction.productID) {
                return transaction.expirationDate
            }
        }
        return nil
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "Unverified transaction", code: 0)
        case .verified(let safe):
            return safe
        }
    }

    private static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "Unverified transaction", code: 0)
        case .verified(let safe):
            return safe
        }
    }

    func manageSubscriptions() async throws {
        // Find an active UIWindowScene and present Apple's manage subscriptions sheet
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            throw NSError(domain: "NoActiveScene", code: 0, userInfo: [NSLocalizedDescriptionKey: "No active scene to present subscriptions"])
        }
        try await AppStore.showManageSubscriptions(in: scene)
    }
}
