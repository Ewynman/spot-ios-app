//
//  DebouncerTests.swift
//  SpotTests
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation
import Testing
@testable import Spot

struct DebouncerTests {

    /// Runs the main run loop for the given duration so DispatchQueue.main work can execute.
    private func runMainLoop(for duration: TimeInterval) async {
        await MainActor.run {
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
        }
    }

    @Test func scheduleRunsBlock() async throws {
        let debouncer = Debouncer(interval: 0.15)
        var ran = false
        debouncer.schedule { ran = true }
        try await Task.sleep(for: .milliseconds(10))  // Let schedule enqueue
        await runMainLoop(for: 0.35)
        #expect(ran)
    }

    @Test func cancelPreventsExecution() async throws {
        let debouncer = Debouncer(interval: 10.0)
        var ran = false
        debouncer.schedule { ran = true }
        debouncer.cancel()
        await runMainLoop(for: 0.25)
        #expect(!ran)
    }

    @Test func scheduleReplacesPrevious() async throws {
        let debouncer = Debouncer(interval: 0.1)
        var first = false
        var second = false
        debouncer.schedule { first = true }
        debouncer.schedule { second = true }
        await runMainLoop(for: 0.2)
        #expect(!first)
        #expect(second)
    }
}
