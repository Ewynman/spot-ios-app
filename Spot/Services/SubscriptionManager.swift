import Foundation
import StoreKit
import UIKit

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

    func purchasePro() async throws {
        isPurchasing = true
        defer { isPurchasing = false }
        let product = try await loadProduct()
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    func refreshEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIds.contains(transaction.productID) {
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
