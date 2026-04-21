//
//  SpotLoggerTests.swift
//  SpotTests
//
//  Tests for the structured SpotLog protocol and SpotLogger.log() method.
//

import Foundation
import Testing
@testable import Spot

struct SpotLoggerTests {

    // MARK: - SpotLog protocol conformance

    @Test func spotServiceLogsConformsToSpotLog() {
        let entry: any SpotLog = SpotServiceLogs.spotFetched
        #expect(entry.tag == "SpotService")
        #expect(entry.level == .info)
        #expect(!entry.message.isEmpty)
    }

    // MARK: - SpotServiceLogs cases

    @Test func spotServiceLogsLevels() {
        #expect(SpotServiceLogs.cachedSpotsReturned.level == .info)
        #expect(SpotServiceLogs.fetchSpotsStarted.level == .debug)
        #expect(SpotServiceLogs.fetchSpotsError.level == .error)
        #expect(SpotServiceLogs.spotDocSkipped.level == .debug)
        #expect(SpotServiceLogs.spotsCachedForMap.level == .info)
        #expect(SpotServiceLogs.storageDeleteFailed.level == .error)
        #expect(SpotServiceLogs.storageDeleted.level == .info)
    }

    @Test func spotServiceLogsMessages() {
        #expect(SpotServiceLogs.cachedSpotsReturned.message == "Returning cached spots")
        #expect(SpotServiceLogs.spotFetched.message == "Fetched spot")
        #expect(SpotServiceLogs.spotNotFound.message == "Spot not found")
        #expect(SpotServiceLogs.fetchSpotsError.message == "fetchSpotsForMap error")
    }

    @Test func spotServiceLogsTags() {
        for logCase in [
            SpotServiceLogs.spotFetched,
            SpotServiceLogs.fetchSpotsError,
            SpotServiceLogs.storageDeleted
        ] {
            #expect(logCase.tag == "SpotService")
        }
    }

    // MARK: - Formatted output

    @Test func logFormattedOutputWithoutDetails() {
        let output = SpotLogger.body(for: SpotServiceLogs.spotFetched, details: [:])
        #expect(output == "SpotLogger: SpotService\nFetched spot")
    }

    @Test func logFormattedOutputWithDetails() {
        let output = SpotLogger.body(for: SpotServiceLogs.spotFetched, details: ["id": "abc123", "statusCode": 200])
        #expect(output.hasPrefix("SpotLogger: SpotService\nFetched spot\n[\n"))
        // Details are sorted alphabetically, each indented with 5 spaces
        #expect(output.contains("     id: abc123"))
        #expect(output.contains("     statusCode: 200"))
        #expect(output.hasSuffix("\n]"))
    }
}
