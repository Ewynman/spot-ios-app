//
//  SupabaseUserService.swift
//  Spot
//
//  Created by Edward Wynman on 4/19/26.
//

import Foundation
import Supabase
import UIKit

/// Syncs the signed-in Supabase Auth user into `public.users` (id = auth user id).
final class SupabaseUserService {
    static let shared = SupabaseUserService()
    private init() {}

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Moderates a JPEG and sets it as the signed-in user's profile photo.
    /// Returns a display URL for immediate UI. The database stores a private
    /// `spot-storage://` reference, not this signed URL.
    func uploadProfileAvatarJPEG(_ data: Data, userId: UUID) async throws -> String {
        let session = try await supabase.auth.session
        guard session.user.id == userId else {
            throw profileAvatarError("You can only update your own profile photo.", code: 403)
        }
        await syncCurrentUser()

        let assetId = UUID()
        let ownerFolder = userId.uuidString.lowercased()
        let path = "\(ownerFolder)/\(assetId.uuidString.lowercased()).jpg"
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

        do {
            try await supabase
                .from("media_assets")
                .insert(MediaAssetInsert(
                    id: assetId,
                    owner_id: userId,
                    kind: "profile_image",
                    status: "pending",
                    pending_bucket: "pending_images",
                    pending_path: path,
                    mime_type: "image/jpeg",
                    byte_size: data.count
                ))
                .execute()
            try await supabase.storage
                .from("pending_images")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUploadFailed, details: [
                "phase": "pending",
                "error": error.localizedDescription
            ])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }

        let moderate: (approved: Bool, reason: String?)
        do {
            moderate = try await SpotSupabaseRepository.invokeModerateImageFunction(mediaAssetId: assetId)
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

        struct AttachParams: Encodable {
            let p_media_asset_id: UUID
        }
        let stored: String
        do {
            stored = try await supabase
                .rpc("set_profile_image_from_approved_asset_v1", params: AttachParams(p_media_asset_id: assetId))
                .execute()
                .value
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUploadFailed, details: [
                "phase": "attach",
                "error": error.localizedDescription
            ])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }

        _ = try? await supabase.storage
            .from("avatars")
            .remove(paths: ["\(ownerFolder)/profile.jpg"])

        guard let display = await ProfileImageDisplayURL.resolve(stored) else {
            SpotLogger.log(SupabaseUserServiceLogs.profileAvatarDisplaySignFailed, details: ["phase": "after_attach"])
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        SpotLogger.log(SupabaseUserServiceLogs.profileAvatarUpdated, details: ["assetId": assetId.uuidString])
        return display
    }

    /// Downloads a provider avatar and runs it through the same moderation path.
    /// Used when auth metadata has a photo and the profile row does not.
    func importRemoteProfileAvatar(from urlString: String, userId: UUID) async throws -> String {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw profileAvatarError("Invalid photo URL.", code: 400)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        guard data.count <= 5_242_880, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw profileAvatarError(ProfileAvatarModerationCopy.unavailable, code: 503)
        }
        return try await uploadProfileAvatarJPEG(jpeg, userId: userId)
    }

    private func profileAvatarError(_ message: String, code: Int) -> NSError {
        NSError(domain: "SpotImageModeration", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Upserts `public.users` for the current session user.
    func syncCurrentUser() async {
        let session: Session
        do {
            session = try await supabase.auth.session
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.syncSkippedNoSession, details: [
                "phase": "session",
                "error": error.localizedDescription
            ])
            return
        }

        let user = session.user
        SpotLogger.log(SupabaseUserServiceLogs.syncStarted, details: ["uid": user.id.uuidString])

        let meta = user.userMetadata
        var username = (meta["username"]?.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if username.isEmpty {
            if let email = user.email, let local = email.split(separator: "@").first, !local.isEmpty {
                username = String(local)
            } else {
                username = "user_\(user.id.uuidString.prefix(8))"
            }
        }
        let usernameLower = username.lowercased()
        let isPrivate = meta["is_private"]?.boolValue ?? false

        let nowString = Self.iso8601.string(from: Date())
        let localeId = Locale.current.identifier
        let emailVerified = user.emailConfirmedAt != nil

        // Write via the `sync_current_user_v1` SECURITY DEFINER RPC rather than a
        // direct PostgREST upsert. The `authenticated` role only has
        // column-scoped UPDATE on public.users (everything except `id`), so an
        // `INSERT ... ON CONFLICT (id) DO UPDATE SET id = excluded.id, ...`
        // upsert is denied for existing rows (SQLSTATE 42501). The RPC derives
        // the id from auth.uid() server-side and only ever writes the caller's
        // own row. See migration 20260702120000_sync_current_user_security_definer_v1.
        struct SyncParams: Encodable {
            let p_username: String
            let p_username_lower: String
            let p_email: String?
            let p_email_verified: Bool
            let p_is_private: Bool
            let p_locale: String
            let p_last_active_at: String
        }

        let params = SyncParams(
            p_username: username,
            p_username_lower: usernameLower,
            p_email: user.email,
            p_email_verified: emailVerified,
            p_is_private: isPrivate,
            p_locale: localeId,
            p_last_active_at: nowString
        )

        do {
            try await supabase
                .rpc("sync_current_user_v1", params: params)
                .execute()
            SpotLogger.log(SupabaseUserServiceLogs.syncSucceeded, details: ["uid": user.id.uuidString])
        } catch {
            let message = error.localizedDescription
            let lower = message.lowercased()
            let isPermissionDenied = lower.contains("permission denied")
                || lower.contains("42501")
                || lower.contains("insufficient privilege")
            if isPermissionDenied {
                SpotLogger.log(SupabaseUserServiceLogs.syncFailedPermissionDenied, details: [
                    "uid": user.id.uuidString,
                    "error": message,
                    "hint": "Grant authenticated INSERT, SELECT, DELETE on public.users; column-scoped UPDATE as in security migration."
                ])
            } else {
                SpotLogger.log(SupabaseUserServiceLogs.syncFailedUpsert, details: [
                    "uid": user.id.uuidString,
                    "error": message
                ])
            }
        }
    }
}
