//
//  ProfileImageReferenceTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import Testing
@testable import Spot

struct ProfileImageReferenceTests {
    @Test func blankValuesAreEmpty() {
        #expect(ProfileImageReference.parse(nil) == nil)
        #expect(ProfileImageReference.parse("   ") == nil)
    }

    @Test func legacyHTTPSURLsPassThrough() {
        let raw = " https://example.com/a.jpg "
        #expect(ProfileImageReference.parse(raw) == .remote("https://example.com/a.jpg"))
    }

    @Test func storageReferenceRoundTrips() {
        let stored = ProfileImageReference.storageValue(
            bucket: "approved_profile_images",
            path: "abc/photo.jpg"
        )
        #expect(stored == "spot-storage://approved_profile_images/abc/photo.jpg")
        #expect(ProfileImageReference.parse(stored) == .storage(bucket: "approved_profile_images", path: "abc/photo.jpg"))
    }

    @Test func brokenStorageReferenceIsRejected() {
        #expect(ProfileImageReference.parse("spot-storage://approved_profile_images") == nil)
        #expect(ProfileImageReference.parse("spot-storage:///photo.jpg") == nil)
    }

    @Test func moderationCopyDistinguishesRejectionFromRetry() {
        #expect(ProfileAvatarModerationCopy.message(approved: true, reason: nil) == nil)
        #expect(ProfileAvatarModerationCopy.message(approved: false, reason: "image_policy_rejected") == ProfileAvatarModerationCopy.rejected)
        #expect(ProfileAvatarModerationCopy.message(approved: false, reason: "moderation_unavailable") == ProfileAvatarModerationCopy.unavailable)
    }
}
