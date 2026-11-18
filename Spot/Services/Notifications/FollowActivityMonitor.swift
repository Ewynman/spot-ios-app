//
//  FollowActivityMonitor.swift
//  Spot
//
//  Created by Edward Wynman on 11/18/26.
//

import Foundation
import Supabase

/// Watches the signed-in user's follow requests and outgoing requests while
/// the app is running, then schedules a local notification on this device.
/// Lock-screen delivery after the process is killed still needs APNs.
@MainActor
final class FollowActivityMonitor {
    static let shared = FollowActivityMonitor()

    private var pollTask: Task<Void, Never>?
    private var activeUserId: String?
    private let pollIntervalNanoseconds: UInt64 = 30_000_000_000

    private init() {}

    func start(userId: String) {
        let normalized = FollowActivityDiff.normalize(userId)
        guard !normalized.isEmpty else {
            stop()
            return
        }
        guard pollTask == nil || activeUserId != normalized else { return }
        stop()
        activeUserId = normalized
        pollTask = Task { [weak self] in
            await self?.loop(userId: normalized)
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        activeUserId = nil
    }

    func refreshNow() {
        guard let activeUserId else { return }
        Task { await self.poll(userId: activeUserId) }
    }

    private func loop(userId: String) async {
        while !Task.isCancelled {
            await poll(userId: userId)
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }

    private func poll(userId: String) async {
        guard !Task.isCancelled else { return }
        guard let uid = UUID(uuidString: userId) else { return }

        let page: FollowRequestsService.Page
        let outgoing: [String]
        do {
            page = try await FollowRequestsService.shared.fetchPage(for: userId, start: 0, pageSize: 100)
            outgoing = try await SocialGraphSupabase.outgoingPendingFollowTargetIds(requesterId: uid)
        } catch {
            SpotLogger.log(NotificationServiceLogs.followActivityPollFailed, details: [
                "error": error.localizedDescription
            ])
            return
        }

        var followed: [String] = []
        var followLookupSucceeded = true
        do {
            followed = try await SocialGraphSupabase.followingIds(followerId: uid)
        } catch {
            followLookupSucceeded = false
            SpotLogger.log(NotificationServiceLogs.followActivityPollFailed, details: [
                "phase": "following",
                "error": error.localizedDescription
            ])
        }

        let storedIncoming = FollowActivityBaselineStore.incomingIDs(userId: userId)
        let storedOutgoing = FollowActivityBaselineStore.outgoingIDs(userId: userId)
        let hasBaseline = storedIncoming != nil && storedOutgoing != nil
        let decision = FollowActivityDiff.decide(
            hasBaseline: hasBaseline,
            previousIncomingIDs: storedIncoming ?? [],
            previousOutgoingIDs: storedOutgoing ?? [],
            unresolvedOutgoingIDs: FollowActivityBaselineStore.unresolvedIDs(userId: userId),
            currentIncoming: page.items.map {
                FollowIncomingNotice(
                    requestID: $0.id,
                    requesterUid: $0.requesterUid,
                    username: $0.username ?? ""
                )
            },
            currentOutgoingIDs: Set(outgoing),
            followedUserIDs: Set(followed),
            followLookupSucceeded: followLookupSucceeded
        )

        FollowActivityBaselineStore.save(
            incoming: decision.nextIncomingIDs,
            outgoing: decision.nextOutgoingIDs,
            unresolved: decision.nextUnresolvedIDs,
            userId: userId
        )

        for notice in decision.incomingToNotify {
            let name = notice.username.trimmingCharacters(in: .whitespacesAndNewlines)
            NotificationService.shared.notifyFollowRequestReceived(
                from: name.isEmpty ? "Someone" : name,
                requesterUid: notice.requesterUid
            )
        }

        if !decision.acceptedUserIds.isEmpty {
            let names = await usernames(for: decision.acceptedUserIds)
            for id in decision.acceptedUserIds {
                NotificationService.shared.notifyFollowRequestAccepted(
                    by: names[id] ?? "Someone",
                    acceptorUid: id
                )
            }
            NotificationCenter.default.post(name: .followGraphDidChange, object: nil)
        }
    }

    private func usernames(for userIds: [String]) async -> [String: String] {
        let uuids = userIds.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [:] }
        struct Row: Decodable {
            let id: UUID
            let username: String
        }
        do {
            let rows: [Row] = try await supabase
                .from(SupabaseTableName.usersPublic)
                .select("id,username")
                .in("id", values: uuids)
                .execute()
                .value
            var names: [String: String] = [:]
            for row in rows {
                let trimmed = row.username.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    names[row.id.uuidString.lowercased()] = trimmed
                }
            }
            return names
        } catch {
            return [:]
        }
    }
}

enum FollowActivityBaselineStore {
    private static func key(_ kind: String, userId: String) -> String {
        "spot.followActivity.v1.\(kind).\(FollowActivityDiff.normalize(userId))"
    }

    static func incomingIDs(userId: String) -> Set<String>? {
        read(kind: "incoming", userId: userId)
    }

    static func outgoingIDs(userId: String) -> Set<String>? {
        read(kind: "outgoing", userId: userId)
    }

    static func unresolvedIDs(userId: String) -> Set<String> {
        read(kind: "unresolved", userId: userId) ?? []
    }

    static func save(incoming: Set<String>, outgoing: Set<String>, unresolved: Set<String>, userId: String) {
        write(Array(incoming), kind: "incoming", userId: userId)
        write(Array(outgoing), kind: "outgoing", userId: userId)
        write(Array(unresolved), kind: "unresolved", userId: userId)
    }

    private static func read(kind: String, userId: String) -> Set<String>? {
        guard let stored = UserDefaults.standard.array(forKey: key(kind, userId: userId)) as? [String] else {
            return nil
        }
        return Set(stored)
    }

    private static func write(_ values: [String], kind: String, userId: String) {
        UserDefaults.standard.set(values, forKey: key(kind, userId: userId))
    }
}
