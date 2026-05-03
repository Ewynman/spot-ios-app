import Foundation
import Supabase

struct FollowRequest: Identifiable, Hashable {
    let id: String
    let requesterUid: String
    let username: String?
    let photoURL: String?
    let createdAt: Date?
}

final class FollowRequestsService {
    static let shared = FollowRequestsService()
    private init() {}

    struct Page {
        let items: [FollowRequest]
        /// Pass as `start` for the next `fetchPage` call, or nil when no more pages.
        let nextStart: Int?
    }

    private struct FollowRequestRow: Decodable {
        let id: UUID
        let requester_id: UUID
        let created_at: String
    }

    private struct UserMini: Decodable {
        let id: UUID
        let username: String
        let profile_image_url: String?
    }

    func countPending(targetUserId: String) async throws -> Int {
        guard let target = UUID(uuidString: targetUserId) else { return 0 }
        struct IdRow: Decodable { let id: UUID }
        let rows: [IdRow] = try await supabase
            .from("follow_requests")
            .select("id", head: false)
            .eq("target_user_id", value: target)
            .eq("status", value: "pending")
            .execute()
            .value
        return rows.count
    }

    func fetchPage(for targetUid: String, start: Int, pageSize: Int) async throws -> Page {
        guard let target = UUID(uuidString: targetUid) else {
            return Page(items: [], nextStart: nil)
        }

        let rows: [FollowRequestRow] = try await supabase
            .from("follow_requests")
            .select("id,requester_id,created_at")
            .eq("target_user_id", value: target)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .range(from: start, to: start + pageSize - 1)
            .execute()
            .value

        let requesterIds = rows.map(\.requester_id)
        var usersById: [UUID: UserMini] = [:]
        if !requesterIds.isEmpty {
            let users: [UserMini] = try await supabase
                .from(SupabaseTableName.usersPublic)
                .select("id,username,profile_image_url")
                .in("id", values: requesterIds)
                .execute()
                .value
            for u in users { usersById[u.id] = u }
        }

        let items: [FollowRequest] = rows.map { row in
            let u = usersById[row.requester_id]
            return FollowRequest(
                id: row.id.uuidString,
                requesterUid: row.requester_id.uuidString,
                username: u?.username,
                photoURL: u?.profile_image_url,
                createdAt: SpotSupabaseRepository.parseTimestamptz(row.created_at)
            )
        }

        let nextStart = rows.count == pageSize ? (start + pageSize) : nil
        return Page(items: items, nextStart: nextStart)
    }

    func accept(requesterUid: String, targetUid: String) async throws {
        guard let requester = UUID(uuidString: requesterUid),
              let target = UUID(uuidString: targetUid)
        else {
            throw NSError(domain: "FollowRequestsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid user id"])
        }

        SpotLogger.log(FollowRequestsServiceLogs.followRequestAccepted, details: ["requesterUid": requesterUid])

        struct FollowInsert: Encodable {
            let follower_id: UUID
            let followee_id: UUID
        }

        do {
            try await supabase
                .from("follows")
                .insert(FollowInsert(follower_id: requester, followee_id: target))
                .execute()
        } catch {
            // Idempotent: edge may already exist.
        }

        try await supabase
            .from("follow_requests")
            .delete()
            .eq("requester_id", value: requester)
            .eq("target_user_id", value: target)
            .eq("status", value: "pending")
            .execute()

        await AuthorPrivacyCache.shared.invalidate(authorId: requesterUid)
    }

    func deny(requesterUid: String, targetUid: String) async throws {
        guard let requester = UUID(uuidString: requesterUid),
              let target = UUID(uuidString: targetUid)
        else {
            throw NSError(domain: "FollowRequestsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid user id"])
        }

        SpotLogger.log(FollowRequestsServiceLogs.followRequestDenied, details: ["requesterUid": requesterUid])

        try await supabase
            .from("follow_requests")
            .delete()
            .eq("requester_id", value: requester)
            .eq("target_user_id", value: target)
            .eq("status", value: "pending")
            .execute()
    }
}
