import Foundation

extension Notification.Name {
    static let showPaywall = Notification.Name("SpotShowPaywall")
    /// Posted when a spot is successfully posted (e.g. from Post tab) so Feed can refresh and show toast.
    static let spotDidPostSuccess = Notification.Name("SpotDidPostSuccess")
    static let spotDidPostFailed = Notification.Name("SpotDidPostFailed")
    /// Posted after the user becomes Pro (e.g. web checkout success) so Root can present post-purchase onboarding if needed.
    static let showPostPurchaseProOnboarding = Notification.Name("SpotShowPostPurchaseProOnboarding")
    /// Posted when `Transaction.updates` delivers a verified Spot Pro transaction that was finished on-device (e.g. purchase completed while UI was not awaiting `Product.purchase()`).
    static let spotStoreKitProEntitlementReady = Notification.Name("SpotStoreKitProEntitlementReady")
}

enum PaywallRouter {
    static func show() {
        NotificationCenter.default.post(name: .showPaywall, object: nil)
    }
}
