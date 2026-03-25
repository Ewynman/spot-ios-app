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
    @Published var hasProduct: Bool = false

    // Try current and legacy IDs to avoid config mismatches during setup
    let productIds: [String] = ["spotPro", "spot.pro.yearly"]

    private var cachedProduct: Product?

    func loadProduct() async throws -> Product {
        if let p = cachedProduct { return p }
        let products = try await Product.products(for: productIds)
        guard let product = products.first else {
            SpotLogger.error("StoreKit: No matching product found", details: ["ids": productIds])
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
            SpotLogger.error("StoreKit ensureProductLoaded failed: \(error.localizedDescription)")
        }
    }

    enum PurchaseProResult: Sendable {
        case purchased
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
            await transaction.finish()
            return .purchased
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            SpotLogger.error(
                "StoreKit: Unhandled Product.PurchaseResult",
                details: ["hint": "Future StoreKit may add cases; update SubscriptionManager.purchasePro"]
            )
            throw SubscriptionPurchaseError.unknownPurchaseOutcome
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
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
