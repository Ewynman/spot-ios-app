import Foundation

/// Simple on-device ranker and blender.
/// - Pool A: recent (time decay)
/// - Pool C: trending (uses trendingScore if present)
/// Blends A:C with fixed ratio and removes duplicates.
final class FeedRanker {
    static let shared = FeedRanker()
    private init() {}

    private let recentWeight: Double = 0.6
    private let trendingWeight: Double = 0.4

    func rankRecent(_ spots: [Spot]) -> [Spot] {
        return spots.sorted { (l, r) in
            (l.createdAt ?? Date.distantPast) > (r.createdAt ?? Date.distantPast)
        }
    }

    func rankTrending(_ spots: [Spot]) -> [Spot] {
        return spots.sorted { (l, r) in
            let lt = Double(l.likes ?? 0) + (l.createdAt?.timeIntervalSince1970 ?? 0) * 0.000001
            let rt = Double(r.likes ?? 0) + (r.createdAt?.timeIntervalSince1970 ?? 0) * 0.000001
            return lt > rt
        }
    }

    func blend(recent: [Spot], trending: [Spot], pageSize: Int) -> [Spot] {
        let rCount = Int((Double(pageSize) * recentWeight).rounded())
        let tCount = pageSize - rCount
        var picked: [Spot] = []
        var seen = Set<String>()

        func push(_ s: Spot) {
            guard let id = s.id else { return }
            guard !seen.contains(id) else { return }
            picked.append(s)
            seen.insert(id)
        }

        for s in recent.prefix(rCount) { push(s) }
        for s in trending.prefix(tCount) { push(s) }

        // Backfill if underfilled
        if picked.count < pageSize {
            for s in recent where picked.count < pageSize { push(s) }
            for s in trending where picked.count < pageSize { push(s) }
        }
        return picked
    }
}


