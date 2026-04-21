//
//  FeedRepository.swift
//  Spot
//
//  Home feed: Supabase candidates + ranker + privacy.
//

import Foundation
import Supabase
import _LocationEssentials

final class FeedRepository: ObservableObject {
    static let shared = FeedRepository()
    private init() {}

    @Published private(set) var spots: [Spot] = []

    private var globalNextOffset: Int = 0
    private var globalExhausted = false

    private var followeeNextOffsetByChunk: [Int: Int] = [:]
    private var followeeChunkDone: Set<Int> = []
    private var followeeMoreAvailable = false

    private let ranker = FeedRanker.shared
    private let pageSize = FeedFlags.pageSize
    private let privacy = AuthorPrivacyCache.shared
    private var seenSpotIds: Set<String> = []

    var moreAvailable: Bool {
        !globalExhausted || followeeMoreAvailable
    }

    func loadInitial() async {
        PerfMetrics.shared.mark("t_first_item")

        globalNextOffset = 0
        globalExhausted = false
        followeeNextOffsetByChunk = [:]
        followeeChunkDone = []
        followeeMoreAvailable = false
        seenSpotIds = []

        FeedDiagnostics.logColdStart(seenSetSize: 0, isApplied: false)

        do {
            guard let uidString = SpotAuthBridge.currentUserId, let uid = UUID(uuidString: uidString) else {
                SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": "No user id"])
                return
            }
            let (followeeIds, _) = try await SocialGraphSupabase.socialLists(for: uid)
            let followeesSet = Set(followeeIds)

            async let gItems = SpotSupabaseRepository.fetchGlobalFeedSpots(limit: pageSize, offset: 0)
            async let fPack = fetchFolloweeSpotsMerged(followeeIds: followeeIds)
            let (g, f) = try await (gItems, fPack)

            advanceGlobalState(fetched: g)
            followeeNextOffsetByChunk = f.nextOffsets
            followeeChunkDone = f.doneChunks
            followeeMoreAvailable = f.hasMore

            await privacy.warm(authorIds: Set((g + f.items).compactMap { $0.userId }))
            let gatedGlobal = await privacy.filter(spots: g)
            let gatedFollowees = await privacy.filter(spots: f.items)

            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: await currentUserVibeStats(userId: uid),
                userLocation: currentUserLocation(),
                seenSpotIds: seenSpotIds
            )
            let rankedFollowees = gatedFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let rankedGlobal = gatedGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }

            let blended = ranker.blend(followees: rankedFollowees, global: rankedGlobal, pageSize: pageSize, creatorCap: 2)

            SpotLogger.log(FeedRepositoryLogs.loadInitial, details: [
                "followees": rankedFollowees.count,
                "global": rankedGlobal.count,
                "blended": blended.count
            ])
            await MainActor.run { self.spots = blended }
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": error.localizedDescription])
        }
    }

    func loadMore() async {
        do {
            guard let uidString = SpotAuthBridge.currentUserId, let uid = UUID(uuidString: uidString) else { return }
            let (followeeIds, _) = try await SocialGraphSupabase.socialLists(for: uid)
            let followeesSet = Set(followeeIds)

            let g: [Spot]
            if globalExhausted {
                g = []
            } else {
                g = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: pageSize, offset: globalNextOffset)
                advanceGlobalState(fetched: g)
            }

            let f = try await fetchFolloweeSpotsMerged(followeeIds: followeeIds)
            for (k, v) in f.nextOffsets { followeeNextOffsetByChunk[k] = v }
            followeeChunkDone.formUnion(f.doneChunks)
            followeeMoreAvailable = f.hasMore

            await privacy.warm(authorIds: Set((g + f.items).compactMap { $0.userId }))
            let gatedGlobal = await privacy.filter(spots: g)
            let gatedFollowees = await privacy.filter(spots: f.items)

            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: await currentUserVibeStats(userId: uid),
                userLocation: currentUserLocation(),
                seenSpotIds: seenSpotIds
            )
            let rankedFollowees = gatedFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let rankedGlobal = gatedGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let blended = ranker.blend(followees: rankedFollowees, global: rankedGlobal, pageSize: pageSize, creatorCap: 2)

            let existingIds = Set(self.spots.compactMap { $0.id })
            let newUnique = blended.filter { spot in
                if let id = spot.id { return !existingIds.contains(id) }
                return true
            }
            SpotLogger.log(FeedRepositoryLogs.loadMore, details: [
                "followees": rankedFollowees.count,
                "global": rankedGlobal.count,
                "appending": newUnique.count
            ])
            await MainActor.run { self.spots.append(contentsOf: newUnique) }
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: ["error": error.localizedDescription])
        }
    }

    private func advanceGlobalState(fetched: [Spot]) {
        globalNextOffset += fetched.count
        if fetched.count < pageSize {
            globalExhausted = true
        }
    }

    private struct FolloweeFetchPack {
        let items: [Spot]
        let nextOffsets: [Int: Int]
        let doneChunks: Set<Int>
        let hasMore: Bool
    }

    private func fetchFolloweeSpotsMerged(followeeIds: [String]) async throws -> FolloweeFetchPack {
        guard !followeeIds.isEmpty else {
            return FolloweeFetchPack(items: [], nextOffsets: [:], doneChunks: [], hasMore: false)
        }

        let chunks: [[String]] = stride(from: 0, to: followeeIds.count, by: 10).map {
            Array(followeeIds[$0..<min($0 + 10, followeeIds.count)])
        }

        let offsetsSnapshot = followeeNextOffsetByChunk
        let doneSnapshot = followeeChunkDone

        var results: [Spot] = []
        var newOffsets: [Int: Int] = [:]
        var done: Set<Int> = []
        var countByChunk: [Int: Int] = [:]

        try await withThrowingTaskGroup(of: (Int, [Spot]).self) { group in
            for (idx, ids) in chunks.enumerated() {
                if doneSnapshot.contains(idx) {
                    group.addTask { (idx, []) }
                    continue
                }
                group.addTask {
                    let uuids = ids.compactMap { UUID(uuidString: $0) }
                    guard !uuids.isEmpty else { return (idx, []) }
                    let prev = offsetsSnapshot[idx] ?? 0
                    let spots = try await SpotSupabaseRepository.fetchFeedSpotsForAuthors(
                        userIds: uuids,
                        limit: self.pageSize,
                        offset: prev
                    )
                    return (idx, spots)
                }
            }

            for try await (idx, spots) in group {
                results.append(contentsOf: spots)
                countByChunk[idx] = spots.count
                let prev = offsetsSnapshot[idx] ?? 0
                if spots.isEmpty {
                    done.insert(idx)
                } else if spots.count < pageSize {
                    done.insert(idx)
                } else {
                    newOffsets[idx] = prev + spots.count
                }
            }
        }

        let hasMore = countByChunk.contains { idx, cnt in
            !done.contains(idx) && cnt == pageSize
        }

        results.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return FolloweeFetchPack(items: results, nextOffsets: newOffsets, doneChunks: done, hasMore: hasMore)
    }

    private func currentUserVibeStats(userId: UUID) async -> [String: Int] {
        struct VibeStatsRow: Decodable { let vibe_stats: [String: Int]? }
        do {
            let row: VibeStatsRow = try await supabase
                .from("users")
                .select("vibe_stats")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            return row.vibe_stats ?? [:]
        } catch {
            return [:]
        }
    }

    private func currentUserLocation() -> CLLocation? { LocationManager.shared.userLocation }
}
