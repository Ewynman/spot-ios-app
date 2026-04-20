//
//  SupabaseUserService.swift
//  Spot
//
//  Created By Edward Wynman on 4/19/2026.
//

import Foundation
import Supabase

/// Syncs the signed-in Supabase Auth user into `public.users` (id = auth user id).
final class SupabaseUserService {
    static let shared = SupabaseUserService()
    private init() {}

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Uploads a JPEG to the `avatars` bucket; returns public URL string.
    func uploadProfileAvatarJPEG(_ data: Data, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/profile.jpg"
        try await supabase.storage
            .from("avatars")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        let url = try supabase.storage.from("avatars").getPublicURL(path: path)
        return url.absoluteString
    }

    /// Upserts `public.users` for the current session user.
    func syncCurrentUser() async {
        let session: Session
        do {
            session = try await supabase.auth.session
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.syncFailed, details: [
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

        struct UserUpsert: Encodable {
            let id: UUID
            let email: String?
            let email_verified: Bool
            let username: String
            let username_lower: String
            let is_private: Bool
            let last_active_at: String
            let locale: String
        }

        let payload = UserUpsert(
            id: user.id,
            email: user.email,
            email_verified: emailVerified,
            username: username,
            username_lower: usernameLower,
            is_private: isPrivate,
            last_active_at: nowString,
            locale: localeId
        )

        do {
            try await supabase
                .from("users")
                .upsert(payload, onConflict: "id")
                .execute()
            SpotLogger.log(SupabaseUserServiceLogs.syncSucceeded, details: ["uid": user.id.uuidString])
        } catch {
            SpotLogger.log(SupabaseUserServiceLogs.syncFailed, details: [
                "uid": user.id.uuidString,
                "error": error.localizedDescription
            ])
        }
    }
}
