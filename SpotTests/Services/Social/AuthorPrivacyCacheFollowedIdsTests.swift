//
//  AuthorPrivacyCacheFollowedIdsTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Testing
@testable import Spot

@Suite(.serialized)
struct AuthorPrivacyCacheFollowedIdsTests {
    @Test func signedOutViewerGetsAnEmptySet() async {
        SpotAuthBridge.setSessionUser(id: nil, email: nil)
        defer { SpotAuthBridge.setSessionUser(id: nil, email: nil) }
        let ids = await AuthorPrivacyCache.shared.currentFollowedUserIds(loadFollowing: { _ in
            Issue.record("Signed-out viewers must not load follows")
            return ["someone"]
        })
        #expect(ids.isEmpty)
    }

    @Test func nonUUIDViewerGetsAnEmptySet() async {
        SpotAuthBridge.setSessionUser(id: "not-a-uuid", email: nil)
        defer { SpotAuthBridge.setSessionUser(id: nil, email: nil) }
        let ids = await AuthorPrivacyCache.shared.currentFollowedUserIds(loadFollowing: { _ in
            ["someone"]
        })
        #expect(ids.isEmpty)
    }

    @Test func followedIdsAreLowercasedAndKeptWhenTheNextLoadFails() async {
        let viewer = UUID()
        SpotAuthBridge.setSessionUser(id: viewer.uuidString, email: nil)
        defer { SpotAuthBridge.setSessionUser(id: nil, email: nil) }

        let loaded = await AuthorPrivacyCache.shared.currentFollowedUserIds(loadFollowing: { uid in
            #expect(uid == viewer)
            return ["AbC"]
        })
        #expect(loaded == ["abc"])

        let kept = await AuthorPrivacyCache.shared.currentFollowedUserIds(loadFollowing: { _ in
            throw NSError(domain: "test", code: 1)
        })
        #expect(kept == ["abc"])
    }

    @Test func followChangePostsAGraphNotification() async {
        let saw = NoteFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .followGraphDidChange,
            object: nil,
            queue: nil
        ) { _ in
            saw.flag = true
        }
        defer { NotificationCenter.default.removeObserver(token) }
        await AuthorPrivacyCache.shared.onFollowRelationshipChanged(followeeUserId: "author")
        #expect(saw.flag)
    }
}

private final class NoteFlag: @unchecked Sendable {
    var flag = false
}
