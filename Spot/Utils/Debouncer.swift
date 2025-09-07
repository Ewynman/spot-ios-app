import Foundation

final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let interval: TimeInterval

    init(interval: TimeInterval = 0.3) {
        self.interval = interval
    }

    func schedule(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
