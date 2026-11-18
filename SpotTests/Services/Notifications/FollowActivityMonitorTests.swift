//
//  FollowActivityMonitorTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Testing
@testable import Spot

@MainActor
private final class FakeFollowActivityReader: FollowActivityReading {
    var pending: Result<[FollowIncomingNotice], Error> = .success([])
    var outgoing: Result<[String], Error> = .success([])
    var following: Result<[String], Error> = .success([])
    var names: Result<[String: String], Error> = .success([:])
    var pendingCalls = 0

    func pendingRequests(userId: String) async throws -> [FollowIncomingNotice] {
        pendingCalls += 1
        return try pending.get()
    }

    func outgoingPendingIds(userId: UUID) async throws -> [String] {
        try outgoing.get()
    }

    func followingIds(userId: UUID) async throws -> [String] {
        try following.get()
    }

    func usernames(for userIds: [String]) async throws -> [String: String] {
        try names.get()
    }
}

@Suite(.serialized)
@MainActor
struct FollowActivityMonitorTests {
    private func monitor(_ reader: FakeFollowActivityReader, interval: UInt64 = 60_000_000_000) -> FollowActivityMonitor {
        FollowActivityMonitor(pollIntervalNanoseconds: interval, reader: reader)
    }

    @Test func blankUserIdStopsTheMonitor() {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        activity.start(userId: "   ")
        #expect(reader.pendingCalls == 0)
    }

    @Test func startingTheSameUserDoesNotReplaceTheLoop() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader, interval: 60_000_000_000)
        let userId = UUID().uuidString
        activity.start(userId: userId)
        activity.start(userId: userId)
        await waitUntil { reader.pendingCalls >= 1 }
        let calls = reader.pendingCalls
        activity.start(userId: userId.lowercased())
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(reader.pendingCalls == calls)
        activity.stop()
    }

    @Test func refreshNowDoesNothingUntilStarted() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        await activity.refreshNow()
        #expect(reader.pendingCalls == 0)
    }

    @Test func loopPollsUntilStopped() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader, interval: 5_000_000)
        activity.start(userId: UUID().uuidString)
        await waitUntil { reader.pendingCalls >= 2 }
        activity.stop()
        #expect(reader.pendingCalls >= 2)
    }

    @Test func refreshNowPollsTheActiveUser() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        let userId = UUID().uuidString
        activity.start(userId: userId)
        await activity.refreshNow()
        activity.stop()
        #expect(reader.pendingCalls >= 1)
    }

    @Test func invalidUserIdDoesNotReadTheGraph() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        await activity.poll(userId: "not-a-uuid")
        #expect(reader.pendingCalls == 0)
    }

    @Test func failedRequestFetchLeavesTheBaselineUnset() async {
        let reader = FakeFollowActivityReader()
        reader.pending = .failure(NSError(domain: "test", code: 1))
        let activity = monitor(reader)
        let userId = UUID().uuidString.lowercased()
        await activity.poll(userId: userId)
        #expect(FollowActivityBaselineStore.incomingIDs(userId: userId) == nil)
    }

    @Test func newRequestAfterBaselineNotifiesAndPersists() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        let userId = UUID().uuidString.lowercased()
        let first = FollowIncomingNotice(requestID: "r1", requesterUid: "u1", username: "Ada")
        reader.pending = .success([first])
        await activity.poll(userId: userId)

        reader.pending = .success([
            first,
            FollowIncomingNotice(requestID: "r2", requesterUid: "u2", username: "  ")
        ])
        await activity.poll(userId: userId)
        #expect(FollowActivityBaselineStore.incomingIDs(userId: userId) == ["r1", "r2"])
    }

    @Test func failedFollowLookupKeepsTheOutgoingRequestUnresolved() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        let userId = UUID().uuidString.lowercased()
        reader.outgoing = .success(["target"])
        await activity.poll(userId: userId)

        reader.outgoing = .success([])
        reader.following = .failure(NSError(domain: "test", code: 2))
        await activity.poll(userId: userId)
        #expect(FollowActivityBaselineStore.unresolvedIDs(userId: userId) == ["target"])
    }

    @Test func acceptedFollowNotifiesAndPostsGraphChange() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        let userId = UUID().uuidString.lowercased()
        reader.outgoing = .success(["target"])
        await activity.poll(userId: userId)

        reader.outgoing = .success([])
        reader.following = .success(["target"])
        reader.names = .success(["target": "Bea"])
        let sawGraphChange = NoteFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .followGraphDidChange,
            object: nil,
            queue: nil
        ) { _ in
            sawGraphChange.flag = true
        }
        defer { NotificationCenter.default.removeObserver(token) }
        await activity.poll(userId: userId)
        #expect(sawGraphChange.flag)
        #expect(FollowActivityBaselineStore.outgoingIDs(userId: userId) == [])
    }

    @Test func usernameLookupFailureStillNotifiesAcceptance() async {
        let reader = FakeFollowActivityReader()
        let activity = monitor(reader)
        let userId = UUID().uuidString.lowercased()
        reader.outgoing = .success(["target"])
        await activity.poll(userId: userId)
        reader.outgoing = .success([])
        reader.following = .success(["target"])
        reader.names = .failure(NSError(domain: "test", code: 3))
        await activity.poll(userId: userId)
        #expect(FollowActivityBaselineStore.unresolvedIDs(userId: userId).isEmpty)
    }

    @Test func baselineStoreRoundTripsAndTreatsMissingAsUnset() {
        let userId = "User-\(UUID().uuidString)"
        #expect(FollowActivityBaselineStore.incomingIDs(userId: userId) == nil)
        #expect(FollowActivityBaselineStore.unresolvedIDs(userId: userId).isEmpty)
        FollowActivityBaselineStore.save(incoming: ["a"], outgoing: [], unresolved: ["b"], userId: userId)
        #expect(FollowActivityBaselineStore.incomingIDs(userId: userId.lowercased()) == ["a"])
        #expect(FollowActivityBaselineStore.outgoingIDs(userId: userId) == [])
        #expect(FollowActivityBaselineStore.unresolvedIDs(userId: userId) == ["b"])
    }

    @Test func invalidUsernameIdsDoNotQuery() async throws {
        let names = try await SupabaseFollowActivityReader().usernames(for: ["not-a-uuid"])
        #expect(names.isEmpty)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class NoteFlag: @unchecked Sendable {
    var flag = false
}
