//
//  DebouncerTests.swift
//  SpotTests
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Testing
@testable import Spot

struct DebouncerTests {

    @Test func scheduleRunsBlock() async throws {
        let debouncer = Debouncer(interval: 0.1)
        var ran = false
        debouncer.schedule { ran = true }
        try await Task.sleep(for: .milliseconds(200))
        #expect(ran)
    }

    @Test func cancelPreventsExecution() async throws {
        let debouncer = Debouncer(interval: 10.0)
        var ran = false
        debouncer.schedule { ran = true }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!ran)
    }

    @Test func scheduleReplacesPrevious() async throws {
        let debouncer = Debouncer(interval: 0.1)
        var first = false
        var second = false
        debouncer.schedule { first = true }
        debouncer.schedule { second = true }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!first)
        #expect(second)
    }
}
