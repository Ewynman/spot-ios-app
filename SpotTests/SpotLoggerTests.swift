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

    @Test func spotUploaderLogsConformsToSpotLog() {
        let entry: any SpotLog = SpotUploaderLogs.spotCreated
        #expect(entry.tag == "SpotUploader")
        #expect(entry.level == .info)
        #expect(!entry.message.isEmpty)
    }

    @Test func spotServiceLogsConformsToSpotLog() {
        let entry: any SpotLog = SpotServiceLogs.spotFetched
        #expect(entry.tag == "SpotService")
        #expect(entry.level == .info)
        #expect(!entry.message.isEmpty)
    }

    // MARK: - SpotUploaderLogs cases

    @Test func spotUploaderLogsLevels() {
        #expect(SpotUploaderLogs.vibeStatIncrement.level == .debug)
        #expect(SpotUploaderLogs.vibeStatFetchFailed.level == .error)
        #expect(SpotUploaderLogs.vibeStatUpdated.level == .info)
        #expect(SpotUploaderLogs.notAuthenticated.level == .error)
        #expect(SpotUploaderLogs.spotCreated.level == .info)
        #expect(SpotUploaderLogs.spotDocumentCreationFailed.level == .error)
        #expect(SpotUploaderLogs.orphanedImageCleanupFailed.level == .debug)
        #expect(SpotUploaderLogs.authorIsPrivateDenormalizationFailed.level == .debug)
    }

    @Test func spotUploaderLogsMessages() {
        #expect(SpotUploaderLogs.spotCreated.message == "Spot upload success")
        #expect(SpotUploaderLogs.spotUpdated.message == "Spot updated")
        #expect(SpotUploaderLogs.notAuthenticated.message == "User not authenticated for spot upload")
        #expect(SpotUploaderLogs.imageConversionFailed.message == "Image conversion failed for spot upload")
    }

    @Test func spotUploaderLogsTags() {
        for logCase in [
            SpotUploaderLogs.spotCreated,
            SpotUploaderLogs.spotDocumentCreationFailed,
            SpotUploaderLogs.notAuthenticated
        ] {
            #expect(logCase.tag == "SpotUploader")
        }
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
}
