import Foundation

/// UserInfo key for `Notification.Name.mainTabReselectSame` — `Int` tab index (matches `BottomTabNavigationView` cases: 0 Home … 4 Profile).
enum SpotMainTabNotification {
    static let userInfoTabIndexKey = "tabIndex"
}

/// `userInfo` keys for `Notification.Name.homeFeedLocallyRemove`.
enum SpotHomeFeedNotification {
    static let spotIdKey = "spotId"
    static let authorUserIdKey = "authorUserId"
}

extension Notification.Name {
    static let showPaywall = Notification.Name("SpotShowPaywall")
    /// Posted when a spot is successfully posted (e.g. from Post tab) so Feed can refresh and show toast.
    static let spotDidPostSuccess = Notification.Name("SpotDidPostSuccess")
    static let spotDidPostFailed = Notification.Name("SpotDidPostFailed")
    /// Posted after the user becomes Pro (e.g. web checkout success) so Root can present post-purchase onboarding if needed.
    static let showPostPurchaseProOnboarding = Notification.Name("SpotShowPostPurchaseProOnboarding")
    /// Posted when `Transaction.updates` delivers a verified Spot Pro transaction that was finished on-device (e.g. purchase completed while UI was not awaiting `Product.purchase()`).
    static let spotStoreKitProEntitlementReady = Notification.Name("SpotStoreKitProEntitlementReady")
    /// Posted when the user taps the already-selected main tab so that tab can scroll to top / pop to root / reset local chrome.
    static let mainTabReselectSame = Notification.Name("SpotMainTabReselectSame")
    /// Remove feed rows immediately after block/report (see `SpotHomeFeedNotification`).
    static let homeFeedLocallyRemove = Notification.Name("SpotHomeFeedLocallyRemove")
}

enum PaywallRouter {
    static func show() {
        NotificationCenter.default.post(name: .showPaywall, object: nil)
    }
}
