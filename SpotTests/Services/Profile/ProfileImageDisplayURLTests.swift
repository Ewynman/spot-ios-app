//
//  ProfileImageDisplayURLTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Testing
@testable import Spot

@Suite(.serialized)
struct ProfileImageDisplayURLTests {
    @Test func blanksAndRemoteURLsResolveWithoutSigning() async {
        let resolved = await ProfileImageDisplayURL.resolveMany(
            [nil, "  ", " https://example.com/a.jpg ", "https://example.com/a.jpg"],
            sign: { _, _ in
                Issue.record("Remote photos must not be signed")
                return []
            }
        )
        #expect(await ProfileImageDisplayURL.resolve("  ") == nil)
        #expect(await ProfileImageDisplayURL.resolve("https://example.com/b.jpg") == "https://example.com/b.jpg")
        #expect(ProfileImageDisplayURL.lookup(nil, in: resolved) == nil)
        #expect(ProfileImageDisplayURL.lookup("https://example.com/a.jpg", in: resolved) == "https://example.com/a.jpg")
    }

    @Test func brokenStorageReferenceIsSkipped() async {
        let resolved = await ProfileImageDisplayURL.resolveMany(
            ["spot-storage://approved_profile_images"],
            sign: { _, _ in
                Issue.record("Unparseable references must not be signed")
                return []
            }
        )
        #expect(resolved.isEmpty)
    }

    @Test func storageReferenceSignsOnceAndThenUsesTheCache() async throws {
        let stored = ProfileImageReference.storageValue(
            bucket: "approved_profile_images",
            path: "owner/\(UUID().uuidString.lowercased()).jpg"
        )
        let signed = URL(string: "https://signed.example/\(UUID().uuidString)")!
        let path = ProfileImageReference.parse(stored).flatMap { ref -> String? in
            if case .storage(_, let path) = ref { return path }
            return nil
        }
        var signCalls = 0
        let sign: ProfileImageDisplayURL.Signer = { _, paths in
            signCalls += 1
            return paths.map { ($0, signed) }
        }
        let first = await ProfileImageDisplayURL.resolveMany([stored, stored], sign: sign)
        let second = await ProfileImageDisplayURL.resolve(stored, sign: sign)
        #expect(signCalls == 1)
        #expect(first[stored] == signed.absoluteString)
        #expect(second == signed.absoluteString)
        #expect(path != nil)
    }

    @Test func unknownSignedPathIsIgnored() async {
        let stored = ProfileImageReference.storageValue(
            bucket: "approved_profile_images",
            path: "owner/\(UUID().uuidString.lowercased()).jpg"
        )
        let resolved = await ProfileImageDisplayURL.resolveMany([stored]) { _, _ in
            [(path: "other/file.jpg", url: URL(string: "https://signed.example/other")!)]
        }
        #expect(ProfileImageDisplayURL.lookup(stored, in: resolved) == nil)
    }

    @Test func signingFailureOmitsThePhoto() async {
        let stored = ProfileImageReference.storageValue(
            bucket: "approved_profile_images",
            path: "owner/\(UUID().uuidString.lowercased()).jpg"
        )
        let resolved = await ProfileImageDisplayURL.resolveMany([stored]) { _, _ in
            throw NSError(domain: "test", code: 1)
        }
        #expect(resolved.isEmpty)
    }
}
