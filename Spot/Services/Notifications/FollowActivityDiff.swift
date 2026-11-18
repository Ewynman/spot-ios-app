//
//  FollowActivityDiff.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation

struct FollowIncomingNotice: Equatable, Sendable {
    let requestID: String
    let requesterUid: String
    let username: String
}

struct FollowActivityDecision: Equatable, Sendable {
    var incomingToNotify: [FollowIncomingNotice]
    var acceptedUserIds: [String]
    var nextIncomingIDs: Set<String>
    var nextOutgoingIDs: Set<String>
    var nextUnresolvedIDs: Set<String>
}

/// Decides which follow events are new for the signed-in device.
/// The first successful observation only records a baseline, so installing
/// the app does not announce every request that already exists.
enum FollowActivityDiff {
    static func decide(
        hasBaseline: Bool,
        previousIncomingIDs: Set<String>,
        previousOutgoingIDs: Set<String>,
        unresolvedOutgoingIDs: Set<String>,
        currentIncoming: [FollowIncomingNotice],
        currentOutgoingIDs: Set<String>,
        followedUserIDs: Set<String>,
        followLookupSucceeded: Bool
    ) -> FollowActivityDecision {
        var seenRequestIDs = Set<String>()
        let incoming = currentIncoming.compactMap { notice -> FollowIncomingNotice? in
            let requestID = normalize(notice.requestID)
            let requesterUid = normalize(notice.requesterUid)
            guard !requestID.isEmpty, !requesterUid.isEmpty else { return nil }
            guard seenRequestIDs.insert(requestID).inserted else { return nil }
            return FollowIncomingNotice(
                requestID: requestID,
                requesterUid: requesterUid,
                username: notice.username
            )
        }
        let currentIncomingIDs = Set(incoming.map(\.requestID))
        let outgoing = Set(currentOutgoingIDs.map(normalize).filter { !$0.isEmpty })
        let followed = Set(followedUserIDs.map(normalize).filter { !$0.isEmpty })
        let previousIncoming = Set(previousIncomingIDs.map(normalize))
        let previousOutgoing = Set(previousOutgoingIDs.map(normalize))
        let unresolved = Set(unresolvedOutgoingIDs.map(normalize))

        if !hasBaseline {
            return FollowActivityDecision(
                incomingToNotify: [],
                acceptedUserIds: [],
                nextIncomingIDs: currentIncomingIDs,
                nextOutgoingIDs: outgoing,
                nextUnresolvedIDs: []
            )
        }

        let incomingToNotify = incoming.filter { !previousIncoming.contains($0.requestID) }
        let candidates = previousOutgoing.union(unresolved).subtracting(outgoing)
        var accepted: [String] = []
        var stillUnresolved = Set<String>()
        for id in candidates.sorted() {
            if followLookupSucceeded, followed.contains(id) {
                accepted.append(id)
            } else if unresolved.contains(id), followLookupSucceeded {
                continue
            } else {
                stillUnresolved.insert(id)
            }
        }

        return FollowActivityDecision(
            incomingToNotify: incomingToNotify,
            acceptedUserIds: accepted,
            nextIncomingIDs: currentIncomingIDs,
            nextOutgoingIDs: outgoing,
            nextUnresolvedIDs: stillUnresolved
        )
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
