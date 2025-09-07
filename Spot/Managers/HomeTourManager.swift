import SwiftUI

final class HomeTourManager: ObservableObject {
    enum Step: Int, CaseIterable {
        case username, location, vibe, likeSave
    }

    // Per-user persistence
    private var storage = UserDefaults.standard
    private var storageKey: String = "hasSeenHomeTour.global"
    @Published var hasSeenHomeTour: Bool = false
    @Published var isWelcomePresented: Bool = false
    @Published var isCoachPresented: Bool = false
    @Published var currentStep: Step = .username

    init(userId: String? = nil) {
        configure(userId: userId)
    }

    func configure(userId: String?) {
        storageKey = "hasSeenHomeTour." + (userId ?? "guest")
        hasSeenHomeTour = storage.bool(forKey: storageKey)
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
