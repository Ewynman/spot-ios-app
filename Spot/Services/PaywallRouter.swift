import Foundation

extension Notification.Name {
    static let showPaywall = Notification.Name("SpotShowPaywall")
    /// Posted when a spot is successfully posted (e.g. from Post tab) so Feed can refresh and show toast.
    static let spotDidPostSuccess = Notification.Name("SpotDidPostSuccess")
}

enum PaywallRouter {
    static func show() {
        NotificationCenter.default.post(name: .showPaywall, object: nil)
    }
}
