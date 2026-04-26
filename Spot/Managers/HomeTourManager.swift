import SwiftUI

final class HomeTourManager: ObservableObject {
    enum Step: Int, CaseIterable {
        case username, location, vibe, likeSave
    }

    private var storage = UserDefaults.standard
    private let storageKey: String = Constants.UserDefaultsKeys.homeTourAccepted
    @Published var hasSeenHomeTour: Bool = false
    @Published var isWelcomePresented: Bool = false
    @Published var isCoachPresented: Bool = false
    @Published var currentStep: Step = .username

    init(userId: String? = nil) {
        configure(userId: userId)
    }

    func configure(userId: String?) {
        hasSeenHomeTour = storage.bool(forKey: storageKey)
        // Migrate old per-user keys so users who already completed tour
        // remain completed after moving to a single global key.
        if !hasSeenHomeTour {
            let legacyKey = "hasSeenHomeTour." + (userId ?? "guest")
            if storage.bool(forKey: legacyKey) {
                storage.set(true, forKey: storageKey)
                hasSeenHomeTour = true
            }
        }
    }

    func startIfNeeded(isFirstSessionAfterSignup: Bool) {
        guard isFirstSessionAfterSignup, !hasSeenHomeTour else { return }
        isWelcomePresented = true
    }

    func startCoach() {
        isWelcomePresented = false
        currentStep = .username
        isCoachPresented = true
    }

    func next() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let next = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        } else {
            complete()
        }
    }

    func skip() {
        complete()
    }

    private func complete() {
        hasSeenHomeTour = true
        storage.set(true, forKey: storageKey)
        isWelcomePresented = false
        isCoachPresented = false
    }
}
