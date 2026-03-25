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

    private final class BoolBox: @unchecked Sendable {
        var value = false
    }

    /// Runs the main run loop for the given duration so DispatchQueue.main work can execute.
    private func runMainLoop(for duration: TimeInterval) async {
        await MainActor.run {
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
        }
    }

    private func pumpMainRunLoop(until deadline: Date, while condition: @escaping @Sendable () -> Bool) async {
        while Date() < deadline, condition() {
            await runMainLoop(for: 0.05)
        }
    }

    @Test func scheduleRunsBlock() async throws {
        let debouncer = Debouncer(interval: 0.15)
        let ran = BoolBox()
        await MainActor.run {
            debouncer.schedule { ran.value = true }
        }
        let deadline = Date().addingTimeInterval(3)
        await pumpMainRunLoop(until: deadline) { !ran.value }
        #expect(ran.value)
    }

    @Test func cancelPreventsExecution() async throws {
        let debouncer = Debouncer(interval: 10.0)
        let ran = BoolBox()
        await MainActor.run {
            debouncer.schedule { ran.value = true }
            debouncer.cancel()
        }
        await runMainLoop(for: 0.25)
        #expect(!ran.value)
    }

    @Test func scheduleReplacesPrevious() async throws {
        let debouncer = Debouncer(interval: 0.1)
        let first = BoolBox()
        let second = BoolBox()
        await MainActor.run {
            debouncer.schedule { first.value = true }
            debouncer.schedule { second.value = true }
        }
        let deadline = Date().addingTimeInterval(3)
        await pumpMainRunLoop(until: deadline) { !second.value }
        #expect(!first.value)
        #expect(second.value)
    }
}
