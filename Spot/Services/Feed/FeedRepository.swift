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
    private let pageSize = 24

    func loadInitial() async {
        PerfMetrics.shared.mark("t_first_item")
        async let recent = candidate.fetchRecent()
        async let trending = candidate.fetchTrending()
        do {
            let (r, t) = try await (recent, trending)
            recentCursor = r.last
            trendingCursor = t.last
            let blended = ranker.blend(recent: ranker.rankRecent(r.items), trending: ranker.rankTrending(t.items), pageSize: pageSize)
            let nilIdRecent = r.items.filter { $0.id == nil }.count
            let nilIdTrending = t.items.filter { $0.id == nil }.count
            SpotLogger.info("Feed loadInitial: recent=\(r.items.count) (nil id=\(nilIdRecent)), trending=\(t.items.count) (nil id=\(nilIdTrending)), blended=\(blended.count)")
            await MainActor.run { self.spots = blended }
            isColdStart = false
        } catch { }
    }

    func loadMore() async {
        do {
            async let r = candidate.fetchRecent(last: recentCursor)
            async let t = candidate.fetchTrending(last: trendingCursor)
            let (nr, nt) = try await (r, t)
            recentCursor = nr.last
            trendingCursor = nt.last
            let blended = ranker.blend(recent: ranker.rankRecent(nr.items), trending: ranker.rankTrending(nt.items), pageSize: pageSize)
            // Prevent duplicates already in feed when appending
            let existingIds = Set(self.spots.compactMap { $0.id })
            let newUnique = blended.filter { spot in
                if let id = spot.id { return !existingIds.contains(id) }
                return true
            }
            SpotLogger.info("Feed loadMore: newRecent=\(nr.items.count), newTrending=\(nt.items.count), blended=\(blended.count), appending=\(newUnique.count)")
            await MainActor.run { self.spots.append(contentsOf: newUnique) }
        } catch { }
    }
}


