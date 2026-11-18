//
//  ProfileAvatarUploadPipeline.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Supabase
import UIKit

struct ProfileAvatarClient {
    var sessionUserId: () async throws -> UUID
    var syncCurrentUser: () async -> Void
    var insertPending: (_ assetId: UUID, _ ownerId: UUID, _ path: String, _ byteCount: Int) async throws -> Void
    var uploadPending: (_ path: String, _ data: Data) async throws -> Void
    var moderate: (_ assetId: UUID) async throws -> (approved: Bool, reason: String?)
    var attach: (_ assetId: UUID) async throws -> String
    var removeLegacyAvatar: (_ path: String) async -> Void
    var displayURL: (_ stored: String) async -> String?
    var download: (_ url: URL) async throws -> (data: Data, statusCode: Int)

    static let live = ProfileAvatarClient(
        sessionUserId: {
            try await supabase.auth.session.user.id
        },
        syncCurrentUser: {
            await SupabaseUserService.shared.syncCurrentUser()
        },
        insertPending: { assetId, ownerId, path, byteCount in
            struct MediaAssetInsert: Encodable {
                let id: UUID
                let owner_id: UUID
                let kind: String
                let status: String
                let pending_bucket: String
                let pending_path: String
                let mime_type: String
                let byte_size: Int
            }
            try await supabase
                .from("media_assets")
                .insert(MediaAssetInsert(
                    id: assetId,
                    owner_id: ownerId,
                    kind: "profile_image",
                    status: "pending",
                    pending_bucket: "pending_images",
                    pending_path: path,
                    mime_type: "image/jpeg",
                    byte_size: byteCount
                ))
                .execute()
        },
        uploadPending: { path, data in
            try await supabase.storage
                .from("pending_images")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        },
        moderate: { assetId in
            try await SpotSupabaseRepository.invokeModerateImageFunction(mediaAssetId: assetId)
        },
        attach: { assetId in
            struct AttachParams: Encodable { let p_media_asset_id: UUID }
            let stored: String = try await supabase
                .rpc("set_profile_image_from_approved_asset_v1", params: AttachParams(p_media_asset_id: assetId))
                .execute()
                .value
            return stored
        },
        removeLegacyAvatar: { path in
            _ = try? await supabase.storage.from("avatars").remove(paths: [path])
        },
        displayURL: { stored in
            await ProfileImageDisplayURL.resolve(stored)
        },
        download: { url in
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        }
    )
}

enum ProfileAvatarUploadPipeline {
    static func upload(
        jpeg data: Data,
        userId: UUID,
        client: ProfileAvatarClient = .live
    ) async throws -> String {
        let sessionUserId: UUID
        do {
            sessionUserId = try await client.sessionUserId()
        } catch {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        guard sessionUserId == userId else {
            throw profileAvatarError("You can only update your own profile photo.", code: 403)
        }
        await client.syncCurrentUser()

        let assetId = UUID()
        let ownerFolder = userId.uuidString.lowercased()
        let path = "\(ownerFolder)/\(assetId.uuidString.lowercased()).jpg"

        do {
            try await client.insertPending(assetId, userId, path, data.count)
            try await client.uploadPending(path, data)
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUploadFailed, details: [
                "phase": "pending",
                "error": error.localizedDescription
            ])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }

        let moderate: (approved: Bool, reason: String?)
        do {
            moderate = try await client.moderate(assetId)
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUploadFailed, details: [
                "phase": "moderate",
                "error": error.localizedDescription
            ])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        if let message = ProfileAvatarModerationCopy.message(approved: moderate.approved, reason: moderate.reason) {
            throw profileAvatarError(message, code: moderate.reason == "image_policy_rejected" ? 422 : 503)
        }

        let stored: String
        do {
            stored = try await client.attach(assetId)
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUploadFailed, details: [
                "phase": "attach",
                "error": error.localizedDescription
            ])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }

        await client.removeLegacyAvatar("\(ownerFolder)/profile.jpg")

        guard let display = await client.displayURL(stored) else {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarDisplaySignFailed, details: ["phase": "after_attach"])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUpdated, details: ["assetId": assetId.uuidString])
        return display
    }

    static func importRemote(
        from urlString: String,
        userId: UUID,
        client: ProfileAvatarClient = .live
    ) async throws -> String {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw profileAvatarError("Invalid photo URL.", code: 400)
        }
        let downloaded: (data: Data, statusCode: Int)
        do {
            downloaded = try await client.download(url)
        } catch {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        guard (200..<300).contains(downloaded.statusCode) else {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        guard downloaded.data.count <= 5_242_880,
              let image = UIImage(data: downloaded.data),
              let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        return try await upload(jpeg: jpeg, userId: userId, client: client)
    }

    static func profileAvatarError(_ message: String, code: Int) -> NSError {
        NSError(domain: "SpotImageModeration", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
