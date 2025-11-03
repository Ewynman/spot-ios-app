import Foundation

extension Notification.Name {
    static let showPaywall = Notification.Name("SpotShowPaywall")
}

enum PaywallRouter {
    static func show() {
        NotificationCenter.default.post(name: .showPaywall, object: nil)
    }
}
