import Foundation
import FirebaseFirestore

final class FeedRepository: ObservableObject {
    static let shared = FeedRepository()
    private init() {}

    @Published private(set) var spots: [Spot] = []
    private var recentCursor: DocumentSnapshot? = nil
    private var trendingCursor: DocumentSnapshot? = nil
    private var isColdStart = true

    private let candidate = FeedCandidateService.shared
    private let ranker = FeedRanker.shared
    private let pageSize = FeedFlags.pageSize
    private let privacy = AuthorPrivacyCache.shared

    func loadInitial() async {
        PerfMetrics.shared.mark("t_first_item")
        
        // Log cold start diagnostics
        FeedDiagnostics.logColdStart(seenSetSize: 0, isApplied: false)
        
        do {
            var accRecent: [Spot] = []
            var accTrending: [Spot] = []
            var rc: DocumentSnapshot? = nil
            var tc: DocumentSnapshot? = nil
            var attempts = 0

            while accRecent.count + accTrending.count < pageSize && attempts < 5 {
                attempts += 1
                let lastRc = rc
                let lastTc = tc
                async let recent = candidate.fetchRecent(last: lastRc)
                async let trending = candidate.fetchTrending(last: lastTc)
                let (r, t) = try await (recent, trending)
                rc = r.last; tc = t.last

                // Warm and filter this batch
                await privacy.warm(authorIds: Set((r.items + t.items).compactMap { $0.userId }))
                let gatedRecent = await privacy.filter(spots: r.items)
                let gatedTrending = await privacy.filter(spots: t.items)
                accRecent.append(contentsOf: gatedRecent)
                accTrending.append(contentsOf: gatedTrending)

                // Stop if both sources exhausted
                if (r.items.isEmpty && t.items.isEmpty) || (rc == nil && tc == nil) { break }
            }

            recentCursor = rc
            trendingCursor = tc

            let nilIdRecent = accRecent.filter { $0.id == nil }.count
            let nilIdTrending = accTrending.filter { $0.id == nil }.count

            let blended = ranker.blend(recent: ranker.rankRecent(accRecent), trending: ranker.rankTrending(accTrending), pageSize: pageSize)

            FeedDiagnostics.logFeedStats(
                recentCount: accRecent.count,
                trendingCount: accTrending.count,
                nilIdCount: nilIdRecent + nilIdTrending,
                excludedByPersistentSeen: 0,
                excludedByBlendSeen: 0,
                excludedByExistingIds: 0
            )
            SpotLogger.info("Feed loadInitial: recent=\(accRecent.count) (nil id=\(nilIdRecent)), trending=\(accTrending.count) (nil id=\(nilIdTrending)), blended=\(blended.count)")
            await MainActor.run { self.spots = blended }
            isColdStart = false
        } catch {
            SpotLogger.error("Feed loadInitial failed: \(error.localizedDescription)")
        }
    }

    func loadMore() async {
        do {
            var pageRecent: [Spot] = []
            var pageTrending: [Spot] = []
            var rc = recentCursor
            var tc = trendingCursor
            var attempts = 0

            while pageRecent.count + pageTrending.count < pageSize && attempts < 5 {
                attempts += 1
                let lastRc = rc
                let lastTc = tc
                async let r = candidate.fetchRecent(last: lastRc)
                async let t = candidate.fetchTrending(last: lastTc)
                let (nr, nt) = try await (r, t)
                rc = nr.last
                tc = nt.last
                await privacy.warm(authorIds: Set((nr.items + nt.items).compactMap { $0.userId }))
                pageRecent.append(contentsOf: await privacy.filter(spots: nr.items))
                pageTrending.append(contentsOf: await privacy.filter(spots: nt.items))
                if (nr.items.isEmpty && nt.items.isEmpty) || (rc == nil && tc == nil) { break }
            }

            recentCursor = rc
            trendingCursor = tc
            let blended = ranker.blend(recent: ranker.rankRecent(pageRecent), trending: ranker.rankTrending(pageTrending), pageSize: pageSize)
            
            // Prevent duplicates already in feed when appending
            let existingIds = Set(self.spots.compactMap { $0.id })
            let excludedByExistingIds = blended.filter { spot in
                if let id = spot.id { return existingIds.contains(id) }
                return false
            }.count
            
            let newUnique = blended.filter { spot in
                if let id = spot.id { return !existingIds.contains(id) }
                return true
            }
            
            // Log exclusion diagnostics
            for spot in blended {
                if let id = spot.id, existingIds.contains(id) {
                    FeedDiagnostics.logExclusion(reason: "existing_id", source: "FeedRepository.loadMore", spot: spot)
                }
            }
            
            SpotLogger.info("Feed loadMore: newRecent=\(pageRecent.count), newTrending=\(pageTrending.count), blended=\(blended.count), excludedByExistingIds=\(excludedByExistingIds), appending=\(newUnique.count)")
            await MainActor.run { self.spots.append(contentsOf: newUnique) }
        } catch {
            SpotLogger.error("Feed loadMore failed: \(error.localizedDescription)")
        }
    }
}


