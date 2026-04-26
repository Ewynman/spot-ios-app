//
//  FeedRepository.swift
//  Spot
//
//  Home feed pipeline.
//
//  v2 path (default): single `get_home_feed_v1` Postgres RPC handles candidate
//  selection, privacy/blocking, dedupe (durable `feed_impressions`), ranking,
//  and pagination. The client only:
//    1. Calls the RPC,
//    2. Signs the primary image for each returned row, and
//    3. Surfaces a load state to the UI so refresh failures don't blank the feed.
//
//  v1 (legacy) path: kept behind `FeedFlags.useSupabaseHomeFeedRPC` for
//  emergency rollback. Logic unchanged.
//

import Foundation
import Supabase
import _LocationEssentials

/// Coarse load state for the homepage feed. Distinct from "is `spots` empty?"
/// because we want to keep the existing list visible during retries and show
/// targeted empty/error overlays only when there is genuinely nothing to show.
enum FeedLoadState: Equatable {
    case idle
    case loadingInitial
    case loadingMore
    case loaded
    /// No items to show, with the reason returned from `get_home_feed_status_v1`.
    case empty(reason: String)
    /// Last load attempt failed. The repository keeps any previously-loaded
    /// spots in `spots` so the UI can show them while the user retries.
    case error(message: String)
}

final class FeedRepository: ObservableObject {
    static let shared = FeedRepository()
    private init() {}

    // MARK: - Published

    @Published private(set) var spots: [Spot] = []
    @Published private(set) var loadState: FeedLoadState = .idle
    /// Latest empty/diagnostic status from `get_home_feed_status_v1`. Used by
    /// the UI to vary the empty-state copy (caught up vs. nothing visible
    /// vs. truly no content).
    @Published private(set) var emptyStatus: HomeFeedStatus? = nil
    /// Surfaced to the UI as a non-blocking toast when a refresh fails after
    /// initial content has been displayed. Cleared on next successful load.
    @Published private(set) var refreshErrorMessage: String? = nil

    // MARK: - State

    /// Whether the next call to `loadMore()` is expected to return new rows.
    /// Set to false only when the server returned 0 rows AND a follow-up
    /// status check confirmed no eligible content exists.
    private(set) var moreAvailable: Bool = true

    /// Number of consecutive `loadMore()` calls that returned 0 new rows.
    /// Used to stop infinite-scroll spam against an exhausted feed.
    private var consecutiveEmptyLoadMore = 0

    /// Local fallback seen-set, only consulted when
    /// `FeedFlags.useServerSideImpressions == false`. Server-side
    /// `feed_impressions` is the authoritative dedupe source.
    private var seenSpotIds: Set<String> = []
    private let persistentSeenKey = "feed.persistentSeen.v1"

    // MARK: - Legacy paging (used only when v2 flag is off)

    private var globalNextOffset: Int = 0
    private var globalExhausted = false
    private var followeeNextOffsetByChunk: [Int: Int] = [:]
    private var followeeChunkDone: Set<Int> = []
    private var followeeMoreAvailable = false
    private let ranker = FeedRanker.shared
    private let pageSize = FeedFlags.pageSize
    private let privacy = AuthorPrivacyCache.shared

    // MARK: - Public API

    func loadInitial() async {
        if FeedFlags.useSupabaseHomeFeedRPC {
            await loadInitialV2()
        } else {
            await loadInitialLegacy()
        }
    }

    func loadMore() async {
        if FeedFlags.useSupabaseHomeFeedRPC {
            await loadMoreV2()
        } else {
            await loadMoreLegacy()
        }
    }

    /// Marks a spot as locally hidden (matches `user_hidden_spots`) and removes
    /// it from the in-memory feed. Useful when the user invokes a "Not
    /// interested" action, since the row will be filtered out server-side on
    /// the next refresh.
    @MainActor
    func locallyRemoveSpot(id: String) {
        spots.removeAll { $0.id == id }
        if spots.isEmpty {
            loadState = .empty(reason: emptyStatus?.status ?? "caught_up")
        }
    }

    /// Inserts a freshly-posted spot at the top of the feed without a refresh.
    /// Intended only for the post-publish flow where the new row hasn't yet
    /// propagated to `get_home_feed_v1` results.
    @MainActor
    func insertSpotAtTop(_ spot: Spot) {
        spots.removeAll { $0.id == spot.id }
        spots.insert(spot, at: 0)
        loadState = .loaded
        emptyStatus = nil
    }

    /// Replaces the current in-memory feed wholesale. Used to roll back an
    /// optimistic delete when the server write fails.
    @MainActor
    func replaceSpots(_ next: [Spot]) {
        spots = next
        loadState = next.isEmpty ? .empty(reason: emptyStatus?.status ?? "caught_up") : .loaded
    }

    /// Clears any in-memory state. Call on sign-out so a different user
    /// doesn't inherit the previous user's feed.
    @MainActor
    func reset() {
        spots = []
        loadState = .idle
        emptyStatus = nil
        refreshErrorMessage = nil
        moreAvailable = true
        consecutiveEmptyLoadMore = 0
        seenSpotIds = []
        globalNextOffset = 0
        globalExhausted = false
        followeeNextOffsetByChunk = [:]
        followeeChunkDone = []
        followeeMoreAvailable = false
    }

    // MARK: - V2 path

    private func loadInitialV2() async {
        PerfMetrics.shared.mark("t_first_item")

        let hadExistingSpots = await MainActor.run { !self.spots.isEmpty }
        await MainActor.run {
            self.loadState = .loadingInitial
            self.refreshErrorMessage = nil
        }

        let location = currentUserLocation()
        do {
            let firstAttempt = try await FeedAPI.fetchHomeFeed(
                limit: pageSize,
                viewerLatitude: location?.coordinate.latitude,
                viewerLongitude: location?.coordinate.longitude,
                forceSeenFallback: false
            )

            // Auto-fallback: if there is no unseen content but the user does
            // have eligible content (status = caught_up), re-run the RPC with
            // forceSeenFallback=true rather than showing the empty state.
            // The seen-fallback bucket re-ranks already-seen rows by least
            // recently shown, so the user keeps getting fresh-feeling content.
            let initialFallbackStatus: HomeFeedStatus?
            let secondAttempt: [HomeFeedRow]
            if firstAttempt.isEmpty {
                let status = try? await FeedAPI.fetchHomeFeedStatus()
                initialFallbackStatus = status
                if status?.status == "caught_up" {
                    SpotLogger.log(FeedSupabaseLogs.loadInitialAutoFallback, details: [
                        "reason": "caught_up_with_eligible_seen",
                        "eligible": status?.eligibleSpots ?? -1
                    ])
                    secondAttempt = (try? await FeedAPI.fetchHomeFeed(
                        limit: pageSize,
                        viewerLatitude: location?.coordinate.latitude,
                        viewerLongitude: location?.coordinate.longitude,
                        forceSeenFallback: true
                    )) ?? []
                } else {
                    secondAttempt = []
                }
            } else {
                initialFallbackStatus = nil
                secondAttempt = []
            }

            let rows = firstAttempt.isEmpty ? secondAttempt : firstAttempt
            let usedSeenFallback = rows.contains { $0.sourceBucket == "seen_fallback" }

            if usedSeenFallback {
                SpotLogger.log(FeedSupabaseLogs.loadInitialUsedSeenFallback, details: [
                    "rows": rows.count
                ])
            }

            let hydrated = await hydrateRows(rows)

            if hydrated.isEmpty {
                let resolvedStatus: HomeFeedStatus?
                if let initialFallbackStatus {
                    resolvedStatus = initialFallbackStatus
                } else {
                    resolvedStatus = try? await FeedAPI.fetchHomeFeedStatus()
                }
                let status = resolvedStatus
                let emptyReason = status?.status ?? "no_eligible_spots"
                await MainActor.run {
                    self.spots = []
                    self.emptyStatus = status
                    self.loadState = .empty(reason: emptyReason)
                    self.moreAvailable = false
                }
                return
            }

            let rowCount = rows.count
            let pageSizeSnapshot = self.pageSize
            await MainActor.run {
                self.spots = hydrated
                self.emptyStatus = nil
                self.loadState = .loaded
                self.moreAvailable = !usedSeenFallback || rowCount == pageSizeSnapshot
                self.consecutiveEmptyLoadMore = 0
            }

            SpotLogger.log(FeedRepositoryLogs.loadInitial, details: [
                "rows": rows.count,
                "hydrated": hydrated.count,
                "usedSeenFallback": usedSeenFallback
            ])
        } catch is CancellationError {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": "cancelled"])
            // Don't touch published state on cancellation; another refresh is
            // already in flight.
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": error.localizedDescription])
            SpotLogger.log(FeedSupabaseLogs.rpcFailed, details: [
                "phase": "loadInitial",
                "preserveOldContent": hadExistingSpots,
                "error": error.localizedDescription
            ])
            await MainActor.run {
                if hadExistingSpots {
                    self.refreshErrorMessage = "Couldn't refresh your feed. Showing previous spots."
                    self.loadState = .loaded
                    SpotLogger.log(FeedSupabaseLogs.loadInitialPreserveOldContent, details: [
                        "remaining": self.spots.count
                    ])
                } else {
                    self.loadState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func loadMoreV2() async {
        let hadExistingSpots = await MainActor.run { !self.spots.isEmpty }
        guard moreAvailable else { return }

        await MainActor.run { self.loadState = .loadingMore }

        let location = currentUserLocation()
        let forceSeenFallback = consecutiveEmptyLoadMore >= 1

        do {
            let rows = try await FeedAPI.fetchHomeFeed(
                limit: pageSize,
                viewerLatitude: location?.coordinate.latitude,
                viewerLongitude: location?.coordinate.longitude,
                forceSeenFallback: forceSeenFallback
            )

            let hydrated = await hydrateRows(rows)
            let existingIds = await MainActor.run { Set(self.spots.compactMap { $0.id }) }
            let newRows = hydrated.filter { spot in
                guard let id = spot.id else { return true }
                return !existingIds.contains(id)
            }

            if newRows.isEmpty {
                consecutiveEmptyLoadMore += 1
                SpotLogger.log(FeedSupabaseLogs.loadMoreNoNewRows, details: [
                    "consecutiveEmpty": consecutiveEmptyLoadMore,
                    "forceSeenFallback": forceSeenFallback
                ])
                await MainActor.run {
                    self.loadState = .loaded
                    if self.consecutiveEmptyLoadMore >= 2 {
                        self.moreAvailable = false
                    }
                }
                return
            }

            consecutiveEmptyLoadMore = 0
            await MainActor.run {
                self.spots.append(contentsOf: newRows)
                self.loadState = .loaded
                self.moreAvailable = true
            }

            SpotLogger.log(FeedRepositoryLogs.loadMore, details: [
                "rows": rows.count,
                "appended": newRows.count
            ])
        } catch is CancellationError {
            SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: ["error": "cancelled"])
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: [
                "error": error.localizedDescription,
                "preserveOldContent": hadExistingSpots
            ])
            await MainActor.run {
                self.loadState = .loaded
                if !hadExistingSpots {
                    self.loadState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    /// Hydrates `HomeFeedRow`s into `Spot`s. With
    /// `FeedFlags.hydrateOnlyPrimaryFeedImage` (default true), only the primary
    /// image URL is signed; full image arrays are loaded lazily on detail.
    private func hydrateRows(_ rows: [HomeFeedRow]) async -> [Spot] {
        guard !rows.isEmpty else { return [] }
        if FeedFlags.hydrateOnlyPrimaryFeedImage {
            let urlMap = await FeedAPI.resolvePrimaryImageURLs(for: rows)
            return rows.map { row in
                row.toSpot(primaryURL: urlMap[row.spotId])
            }
        }
        // Pre-flag-flip behavior: sign each primary inline.
        var hydrated: [Spot] = []
        hydrated.reserveCapacity(rows.count)
        for row in rows {
            let url = await FeedAPI.resolvePrimaryImageURL(
                storagePath: row.primaryStoragePath,
                publicUrl: row.primaryPublicUrl
            )
            hydrated.append(row.toSpot(primaryURL: url))
        }
        return hydrated
    }

    // MARK: - Legacy path (preserved verbatim, gated by flag)

    private func loadInitialLegacy() async {
        PerfMetrics.shared.mark("t_first_item")

        globalNextOffset = 0
        globalExhausted = false
        followeeNextOffsetByChunk = [:]
        followeeChunkDone = []
        followeeMoreAvailable = false
        seenSpotIds = []

        if !FeedFlags.disablePersistentDedupe {
            seenSpotIds = loadPersistentSeen()
            FeedDiagnostics.logColdStart(seenSetSize: seenSpotIds.count, isApplied: true)
        } else {
            FeedDiagnostics.logColdStart(seenSetSize: 0, isApplied: false)
        }

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
            var unseenGlobal = filterUnseen(gatedGlobal)
            let unseenFollowees = filterUnseen(gatedFollowees)
            if unseenGlobal.count < pageSize && !globalExhausted {
                let topUp = await fetchAdditionalGlobalUnseen(targetCount: pageSize - unseenGlobal.count)
                unseenGlobal.append(contentsOf: topUp)
            }

            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: await currentUserVibeStats(userId: uid),
                userLocation: currentUserLocation(),
                seenSpotIds: seenSpotIds
            )
            let rankedFollowees = unseenFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let rankedGlobal = unseenGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }

            var blended = ranker.blend(followees: rankedFollowees, global: rankedGlobal, pageSize: pageSize, creatorCap: 2)
            if blended.isEmpty {
                var fallbackGlobal = gatedGlobal
                if fallbackGlobal.count < pageSize && !globalExhausted {
                    let topUp = await fetchAdditionalGlobal(targetCount: pageSize - fallbackGlobal.count)
                    fallbackGlobal.append(contentsOf: topUp)
                }
                let fallbackFollowees = gatedFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
                let fallbackGlobalRanked = fallbackGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
                blended = ranker.blend(followees: fallbackFollowees, global: fallbackGlobalRanked, pageSize: pageSize, creatorCap: 2)
                SpotLogger.log(FeedRepositoryLogs.loadInitial, details: [
                    "fallbackToSeen": true,
                    "fallbackFollowees": fallbackFollowees.count,
                    "fallbackGlobal": fallbackGlobalRanked.count,
                    "blended": blended.count
                ])
            }
            markSeen(blended)

            let finalBlended = blended
            SpotLogger.log(FeedRepositoryLogs.loadInitial, details: [
                "followees": rankedFollowees.count,
                "global": rankedGlobal.count,
                "blended": finalBlended.count
            ])
            await MainActor.run {
                self.spots = finalBlended
                self.loadState = finalBlended.isEmpty ? .empty(reason: "no_eligible_spots") : .loaded
                self.moreAvailable = !self.globalExhausted || self.followeeMoreAvailable
            }
        } catch is CancellationError {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": "cancelled"])
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": error.localizedDescription])
            await MainActor.run {
                if self.spots.isEmpty {
                    self.loadState = .error(message: error.localizedDescription)
                } else {
                    self.refreshErrorMessage = "Couldn't refresh your feed. Showing previous spots."
                }
            }
        }
    }

    private func loadMoreLegacy() async {
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
            var unseenGlobal = filterUnseen(gatedGlobal)
            let unseenFollowees = filterUnseen(gatedFollowees)
            if unseenGlobal.count < pageSize && !globalExhausted {
                let topUp = await fetchAdditionalGlobalUnseen(targetCount: pageSize - unseenGlobal.count)
                unseenGlobal.append(contentsOf: topUp)
            }

            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: await currentUserVibeStats(userId: uid),
                userLocation: currentUserLocation(),
                seenSpotIds: seenSpotIds
            )
            let rankedFollowees = unseenFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let rankedGlobal = unseenGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let blended = ranker.blend(followees: rankedFollowees, global: rankedGlobal, pageSize: pageSize, creatorCap: 2)

            let existingIds = Set(self.spots.compactMap { $0.id })
            let newUnique = blended.filter { spot in
                if let id = spot.id { return !existingIds.contains(id) }
                return true
            }
            markSeen(newUnique)
            SpotLogger.log(FeedRepositoryLogs.loadMore, details: [
                "followees": rankedFollowees.count,
                "global": rankedGlobal.count,
                "appending": newUnique.count
            ])
            await MainActor.run {
                self.spots.append(contentsOf: newUnique)
                self.loadState = .loaded
                self.moreAvailable = !self.globalExhausted || self.followeeMoreAvailable
            }
        } catch is CancellationError {
            SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: ["error": "cancelled"])
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: ["error": error.localizedDescription])
        }
    }

    private func filterUnseen(_ spots: [Spot]) -> [Spot] {
        guard !seenSpotIds.isEmpty else { return spots }
        return spots.filter { spot in
            guard let id = spot.id else { return true }
            let unseen = !seenSpotIds.contains(id)
            if !unseen {
                FeedDiagnostics.logExclusion(reason: "persistent_seen", source: "FeedRepository.filterUnseen", spot: spot)
            }
            return unseen
        }
    }

    private func markSeen(_ spots: [Spot]) {
        guard !FeedFlags.disablePersistentDedupe else { return }
        let now = Date().timeIntervalSince1970
        var persisted = loadPersistentSeenMap()
        for id in spots.compactMap(\.id) {
            seenSpotIds.insert(id)
            persisted[id] = now
        }
        savePersistentSeenMap(persisted)
    }

    private func loadPersistentSeen() -> Set<String> {
        Set(loadPersistentSeenMap().keys)
    }

    private func loadPersistentSeenMap() -> [String: TimeInterval] {
        guard
            let raw = UserDefaults.standard.dictionary(forKey: persistentSeenKey) as? [String: TimeInterval]
        else { return [:] }
        guard FeedFlags.persistentSeenTTL > 0 else { return raw }
        let now = Date().timeIntervalSince1970
        let maxAge = FeedFlags.persistentSeenTTL * 3600
        return raw.filter { now - $0.value <= maxAge }
    }

    private func savePersistentSeenMap(_ map: [String: TimeInterval]) {
        UserDefaults.standard.set(map, forKey: persistentSeenKey)
    }

    private func fetchAdditionalGlobalUnseen(targetCount: Int) async -> [Spot] {
        guard targetCount > 0 else { return [] }
        var collected: [Spot] = []
        var attempts = 0
        let maxAttempts = 8

        while collected.count < targetCount && !globalExhausted && attempts < maxAttempts {
            attempts += 1
            do {
                let next = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: pageSize, offset: globalNextOffset)
                advanceGlobalState(fetched: next)
                if next.isEmpty { break }
                await privacy.warm(authorIds: Set(next.compactMap { $0.userId }))
                let gated = await privacy.filter(spots: next)
                let unseen = filterUnseen(gated)
                if !unseen.isEmpty {
                    collected.append(contentsOf: unseen)
                }
            } catch {
                SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: [
                    "error": error.localizedDescription,
                    "phase": "global_top_up"
                ])
                break
            }
        }

        if collected.count > targetCount {
            return Array(collected.prefix(targetCount))
        }
        return collected
    }

    private func fetchAdditionalGlobal(targetCount: Int) async -> [Spot] {
        guard targetCount > 0 else { return [] }
        var collected: [Spot] = []
        var attempts = 0
        let maxAttempts = 8

        while collected.count < targetCount && !globalExhausted && attempts < maxAttempts {
            attempts += 1
            do {
                let next = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: pageSize, offset: globalNextOffset)
                advanceGlobalState(fetched: next)
                if next.isEmpty { break }
                await privacy.warm(authorIds: Set(next.compactMap { $0.userId }))
                let gated = await privacy.filter(spots: next)
                if !gated.isEmpty {
                    collected.append(contentsOf: gated)
                }
            } catch {
                SpotLogger.log(FeedRepositoryLogs.loadMoreFailed, details: [
                    "error": error.localizedDescription,
                    "phase": "global_top_up_any"
                ])
                break
            }
        }

        if collected.count > targetCount {
            return Array(collected.prefix(targetCount))
        }
        return collected
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
