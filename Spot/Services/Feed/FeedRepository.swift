import Foundation
import _LocationEssentials
import FirebaseFirestore
import FirebaseAuth

final class FeedRepository: ObservableObject {
    static let shared = FeedRepository()
    private init() {}

    @Published private(set) var spots: [Spot] = []
    private var globalCursor: DocumentSnapshot?
    private var followeeChunkCursors: [Int: DocumentSnapshot?] = [:]
    private var isColdStart = true

    private let candidate = FeedCandidateService.shared
    private let ranker = FeedRanker.shared
    private let pageSize = FeedFlags.pageSize
    private let privacy = AuthorPrivacyCache.shared
    private var seenSpotIds: Set<String> = []

    var moreAvailable: Bool {
        if globalCursor != nil { return true }
        for v in followeeChunkCursors.values { if v != nil { return true } }
        return false
    }

    func loadInitial() async {
        PerfMetrics.shared.mark("t_first_item")

        // Reset cursors and seen spots for fresh feed
        globalCursor = nil
        followeeChunkCursors = [:]
        seenSpotIds = []

        // Log cold start diagnostics
        FeedDiagnostics.logColdStart(seenSetSize: 0, isApplied: false)

        do {
            // Load social lists and current user context
            let (followeeIds, _) = await withCheckedContinuation { cont in
                UserSpotService.shared.getSocialLists(for: nil) { f, r in cont.resume(returning: (f, r)) }
            }
            let followeesSet = Set(followeeIds)

            // Pull candidates in parallel - start fresh with nil cursors
            async let globalPage = candidate.fetchRecent(last: nil)
            async let followeesPage = candidate.fetchFolloweesRecent(followeeIds: followeeIds, lastByChunk: [:])
            let (g, f) = try await (globalPage, followeesPage)
            globalCursor = g.last
            followeeChunkCursors = f.lastByChunk

            // Privacy warm + filter
            await privacy.warm(authorIds: Set((g.items + f.items).compactMap { $0.userId }))
            let gatedGlobal = await privacy.filter(spots: g.items)
            let gatedFollowees = await privacy.filter(spots: f.items)

            // Rank within buckets
            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: currentUserVibeStats(),
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
            isColdStart = false
        } catch {
            SpotLogger.log(FeedRepositoryLogs.loadInitialFailed, details: ["error": error.localizedDescription])
        }
    }

    func loadMore() async {
        do {
            let (followeeIds, _) = await withCheckedContinuation { cont in
                UserSpotService.shared.getSocialLists(for: nil) { f, r in cont.resume(returning: (f, r)) }
            }
            let followeesSet = Set(followeeIds)

            async let g = candidate.fetchRecent(last: globalCursor)
            async let f = candidate.fetchFolloweesRecent(followeeIds: followeeIds, lastByChunk: followeeChunkCursors)
            let (ng, nf) = try await (g, f)
            globalCursor = ng.last
            followeeChunkCursors = nf.lastByChunk

            await privacy.warm(authorIds: Set((ng.items + nf.items).compactMap { $0.userId }))
            let gatedGlobal = await privacy.filter(spots: ng.items)
            let gatedFollowees = await privacy.filter(spots: nf.items)

            let ctx = FeedRanker.Context(
                followeeIds: followeesSet,
                userVibeStats: currentUserVibeStats(),
                userLocation: currentUserLocation(),
                seenSpotIds: seenSpotIds
            )
            let rankedFollowees = gatedFollowees.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let rankedGlobal = gatedGlobal.sorted { ranker.score($0, ctx: ctx) > ranker.score($1, ctx: ctx) }
            let blended = ranker.blend(followees: rankedFollowees, global: rankedGlobal, pageSize: pageSize, creatorCap: 2)

            // Dedup against existing
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

    // MARK: - Context helpers
    private func currentUserVibeStats() -> [String: Int] {
        guard let uid = AuthViewModel().userId ?? Auth.auth().currentUser?.uid else { return [:] }
        let sema = DispatchSemaphore(value: 0)
        var result: [String: Int] = [:]
        Firestore.firestore().collection("users").document(uid).getDocument { snap, _ in
            if let map = snap?.data()? ["vibeStats"] as? [String: Any] {
                var out: [String: Int] = [:]
                for (k, v) in map { if let i = v as? Int { out[k] = i } }
                result = out
            }
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 1.0)
        return result
    }

    private func currentUserLocation() -> CLLocation? { return LocationManager.shared.userLocation }
}
