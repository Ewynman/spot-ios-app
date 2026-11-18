//
//  ProfileAvatarUploadPipelineTests.swift
//  SpotTests
//
//  Created by Edward Wynman on 11/18/26.
//

import UIKit
import Testing
@testable import Spot

@Suite(.serialized)
struct ProfileAvatarUploadPipelineTests {
    private struct Recorder {
        var synced = false
        var inserted = false
        var uploaded = false
        var removedLegacy = false
        var session: Result<UUID, Error>
        var moderate: Result<(Bool, String?), Error> = .success((true, nil))
        var attach: Result<String, Error> = .success("spot-storage://approved_profile_images/owner/a.jpg")
        var display: String? = "https://signed.example/a.jpg"
        var uploadError: Error?
    }

    private func client(_ recorder: Recorder) -> ProfileAvatarClient {
        ProfileAvatarClient(
            sessionUserId: { try recorder.session.get() },
            syncCurrentUser: { },
            insertPending: { _, _, _, _ in },
            uploadPending: { _, _ in
                if let uploadError = recorder.uploadError { throw uploadError }
            },
            moderate: { _ in try recorder.moderate.get() },
            attach: { _ in try recorder.attach.get() },
            removeLegacyAvatar: { _ in },
            displayURL: { _ in recorder.display },
            download: { _ in (Data(), 200) }
        )
    }

    private func error(from body: () async throws -> String) async -> NSError? {
        do {
            _ = try await body()
            return nil
        } catch let error as NSError {
            return error
        } catch {
            return nil
        }
    }

    @Test func sessionFailureIsUnavailable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(session: .failure(NSError(domain: "test", code: 1))))
            )
        }
        #expect(failure?.code == 503)
        #expect(failure?.localizedDescription == ProfileAvatarModerationCopy.unavailable)
    }

    @Test func anotherUsersPhotoIsRejected() async {
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: UUID(),
                client: client(Recorder(session: .success(UUID())))
            )
        }
        #expect(failure?.code == 403)
    }

    @Test func pendingUploadFailureIsUnavailable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(
                    session: .success(userId),
                    uploadError: NSError(domain: "test", code: 9)
                ))
            )
        }
        #expect(failure?.code == 503)
    }

    @Test func moderationTransportFailureIsUnavailable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(
                    session: .success(userId),
                    moderate: .failure(NSError(domain: "test", code: 2))
                ))
            )
        }
        #expect(failure?.code == 503)
    }

    @Test func policyRejectionUsesTheSafeCopy() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(
                    session: .success(userId),
                    moderate: .success((false, "image_policy_rejected"))
                ))
            )
        }
        #expect(failure?.code == 422)
        #expect(failure?.localizedDescription == ProfileAvatarModerationCopy.rejected)
    }

    @Test func otherModerationReasonIsRetryable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(
                    session: .success(userId),
                    moderate: .success((false, "moderation_unavailable"))
                ))
            )
        }
        #expect(failure?.code == 503)
    }

    @Test func attachFailureIsUnavailable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(
                    session: .success(userId),
                    attach: .failure(NSError(domain: "test", code: 4))
                ))
            )
        }
        #expect(failure?.code == 503)
    }

    @Test func missingDisplayURLIsUnavailable() async {
        let userId = UUID()
        let failure = await error {
            try await ProfileAvatarUploadPipeline.upload(
                jpeg: Data([1]),
                userId: userId,
                client: client(Recorder(session: .success(userId), display: nil))
            )
        }
        #expect(failure?.code == 503)
    }

    @Test func approvedPhotoReturnsTheDisplayURLAndRemovesTheLegacyFile() async throws {
        let userId = UUID()
        let removed = LockedFlag()
        let client = ProfileAvatarClient(
            sessionUserId: { userId },
            syncCurrentUser: { },
            insertPending: { _, _, _, _ in },
            uploadPending: { _, _ in },
            moderate: { _ in (true, nil) },
            attach: { _ in "spot-storage://approved_profile_images/owner/a.jpg" },
            removeLegacyAvatar: { path in
                #expect(path == "\(userId.uuidString.lowercased())/profile.jpg")
                await removed.set()
            },
            displayURL: { _ in "https://signed.example/photo.jpg" },
            download: { _ in (Data(), 200) }
        )
        let display = try await ProfileAvatarUploadPipeline.upload(jpeg: Data([1]), userId: userId, client: client)
        #expect(display == "https://signed.example/photo.jpg")
        #expect(await removed.value)
    }

    @Test func remoteImportRejectsNonHTTPSAndBadDownloads() async {
        let userId = UUID()
        let invalid = await error {
            try await ProfileAvatarUploadPipeline.importRemote(from: "http://example.com/a.jpg", userId: userId)
        }
        #expect(invalid?.code == 400)

        let thrown = await error {
            try await ProfileAvatarUploadPipeline.importRemote(
                from: "https://example.com/a.jpg",
                userId: userId,
                client: downloadClient(userId: userId) { _ in throw NSError(domain: "test", code: 1) }
            )
        }
        #expect(thrown?.code == 503)

        let status = await error {
            try await ProfileAvatarUploadPipeline.importRemote(
                from: "https://example.com/a.jpg",
                userId: userId,
                client: downloadClient(userId: userId) { _ in (Data([1, 2, 3]), 500) }
            )
        }
        #expect(status?.code == 503)

        let huge = await error {
            try await ProfileAvatarUploadPipeline.importRemote(
                from: "https://example.com/a.jpg",
                userId: userId,
                client: downloadClient(userId: userId) { _ in (Data(count: 5_242_881), 200) }
            )
        }
        #expect(huge?.code == 503)

        let garbage = await error {
            try await ProfileAvatarUploadPipeline.importRemote(
                from: "https://example.com/a.jpg",
                userId: userId,
                client: downloadClient(userId: userId) { _ in (Data([0, 1, 2, 3]), 200) }
            )
        }
        #expect(garbage?.code == 503)
    }

    @Test func remoteImportUploadsADownloadedJPEG() async throws {
        let userId = UUID()
        let jpeg = tinyJPEG()
        let display = try await ProfileAvatarUploadPipeline.importRemote(
            from: "https://example.com/avatar.jpg",
            userId: userId,
            client: downloadClient(userId: userId) { _ in (jpeg, 200) }
        )
        #expect(display == "https://signed.example/photo.jpg")
    }

    @Test func liveClientStepsFailClosedWithoutASession() async {
        let client = ProfileAvatarClient.live
        let userId = UUID()
        let assetId = UUID()
        _ = try? await client.sessionUserId()
        await client.syncCurrentUser()
        _ = try? await client.insertPending(assetId, userId, "\(userId.uuidString.lowercased())/a.jpg", 1)
        _ = try? await client.uploadPending("\(userId.uuidString.lowercased())/a.jpg", Data([1]))
        _ = try? await client.moderate(assetId)
        _ = try? await client.attach(assetId)
        await client.removeLegacyAvatar("\(userId.uuidString.lowercased())/profile.jpg")
        _ = await client.displayURL("spot-storage://approved_profile_images/owner/a.jpg")
        if let url = URL(string: "https://127.0.0.1:9/avatar.jpg") {
            _ = try? await client.download(url)
        }
    }

    @Test func serviceWrappersRejectANonHTTPSImport() async {
        let failure = await error {
            try await SupabaseUserService.shared.importRemoteProfileAvatar(from: "notaurl", userId: UUID())
        }
        #expect(failure?.code == 400)
    }

    private func downloadClient(
        userId: UUID,
        download: @escaping (URL) async throws -> (data: Data, statusCode: Int)
    ) -> ProfileAvatarClient {
        ProfileAvatarClient(
            sessionUserId: { userId },
            syncCurrentUser: { },
            insertPending: { _, _, _, _ in },
            uploadPending: { _, _ in },
            moderate: { _ in (true, nil) },
            attach: { _ in "stored" },
            removeLegacyAvatar: { _ in },
            displayURL: { _ in "https://signed.example/photo.jpg" },
            download: download
        )
    }

    private func tinyJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

private actor LockedFlag {
    private var flagged = false
    func set() { flagged = true }
    var value: Bool { flagged }
}
