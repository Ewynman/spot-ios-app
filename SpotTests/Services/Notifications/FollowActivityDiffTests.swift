//
//  FollowActivityDiffTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import Testing
@testable import Spot

struct FollowActivityDiffTests {
    private func notice(_ id: String, requester: String, name: String = "ada") -> FollowIncomingNotice {
        FollowIncomingNotice(requestID: id, requesterUid: requester, username: name)
    }

    @Test func firstObservationRecordsBaselineWithoutNotifying() {
        let decision = FollowActivityDiff.decide(
            hasBaseline: false,
            previousIncomingIDs: [],
            previousOutgoingIDs: [],
            unresolvedOutgoingIDs: [],
            currentIncoming: [notice("R1", requester: "U1")],
            currentOutgoingIDs: ["T1"],
            followedUserIDs: [],
            followLookupSucceeded: true
        )
        #expect(decision.incomingToNotify.isEmpty)
        #expect(decision.acceptedUserIds.isEmpty)
        #expect(decision.nextIncomingIDs == ["r1"])
        #expect(decision.nextOutgoingIDs == ["t1"])
        #expect(decision.nextUnresolvedIDs.isEmpty)
    }

    @Test func newIncomingRequestIsNotifiedOnce() {
        let decision = FollowActivityDiff.decide(
            hasBaseline: true,
            previousIncomingIDs: ["r1"],
            previousOutgoingIDs: [],
            unresolvedOutgoingIDs: [],
            currentIncoming: [notice("R1", requester: "U1"), notice("R2", requester: "U2", name: "bea")],
            currentOutgoingIDs: [],
            followedUserIDs: [],
            followLookupSucceeded: true
        )
        #expect(decision.incomingToNotify.map(\.requestID) == ["r2"])
        #expect(decision.incomingToNotify.map(\.username) == ["bea"])
        #expect(decision.nextIncomingIDs == ["r1", "r2"])
    }

    @Test func disappearedOutgoingRequestWaitsOnePollThenDropsIfNotFollowed() {
        let first = FollowActivityDiff.decide(
            hasBaseline: true,
            previousIncomingIDs: [],
            previousOutgoingIDs: ["T1"],
            unresolvedOutgoingIDs: [],
            currentIncoming: [],
            currentOutgoingIDs: [],
            followedUserIDs: [],
            followLookupSucceeded: true
        )
        #expect(first.acceptedUserIds.isEmpty)
        #expect(first.nextUnresolvedIDs == ["t1"])

        let second = FollowActivityDiff.decide(
            hasBaseline: true,
            previousIncomingIDs: [],
            previousOutgoingIDs: [],
            unresolvedOutgoingIDs: first.nextUnresolvedIDs,
            currentIncoming: [],
            currentOutgoingIDs: [],
            followedUserIDs: [],
            followLookupSucceeded: true
        )
        #expect(second.acceptedUserIds.isEmpty)
        #expect(second.nextUnresolvedIDs.isEmpty)
    }

    @Test func acceptedFollowNotifiesOnTheRequesterDevice() {
        let decision = FollowActivityDiff.decide(
            hasBaseline: true,
            previousIncomingIDs: [],
            previousOutgoingIDs: ["Target"],
            unresolvedOutgoingIDs: [],
            currentIncoming: [],
            currentOutgoingIDs: [],
            followedUserIDs: ["TARGET"],
            followLookupSucceeded: true
        )
        #expect(decision.acceptedUserIds == ["target"])
        #expect(decision.nextUnresolvedIDs.isEmpty)
    }

    @Test func failedFollowLookupKeepsTheRequestUnresolved() {
        let decision = FollowActivityDiff.decide(
            hasBaseline: true,
            previousIncomingIDs: [],
            previousOutgoingIDs: [],
            unresolvedOutgoingIDs: ["target"],
            currentIncoming: [],
            currentOutgoingIDs: [],
            followedUserIDs: [],
            followLookupSucceeded: false
        )
        #expect(decision.acceptedUserIds.isEmpty)
        #expect(decision.nextUnresolvedIDs == ["target"])
    }
}
