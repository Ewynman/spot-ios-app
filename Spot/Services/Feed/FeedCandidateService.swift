import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FeedCandidateService {
    static let shared = FeedCandidateService()
    private init() {}

    private let db = Firestore.firestore()
    private let pageSize = FeedFlags.pageSize

    struct Page<T> { let items: [T]; let last: DocumentSnapshot? }

    func fetchRecent(last: DocumentSnapshot? = nil) async throws -> Page<Spot> {
        var q: Query = db.collection("spots").order(by: "createdAt", descending: true).limit(to: pageSize)
        if let last { q = q.start(afterDocument: last) }
        let snap = try await q.getDocuments()
        let items = snap.documents.compactMap { doc in
            var spot = try? doc.data(as: Spot.self)
            // Ensure spot.id is populated from Firestore document ID
            if spot?.id == nil {
                spot?.id = doc.documentID
                FeedDiagnostics.logExclusion(reason: "nil_id_fixed", source: "FeedCandidateService.fetchRecent", spot: spot!)
            }
            return spot
        }
        return Page(items: items, last: snap.documents.last)
    }

    func fetchTrending(last: DocumentSnapshot? = nil) async throws -> Page<Spot> {
        do {
            // If trendingScore absent, fallback to likes desc then createdAt desc
            var q: Query = db.collection("spots").order(by: "likes", descending: true).order(by: "createdAt", descending: true).limit(to: pageSize)
            if let last { q = q.start(afterDocument: last) }
            let snap = try await q.getDocuments()
            let items = snap.documents.compactMap { doc in
                var spot = try? doc.data(as: Spot.self)
                // Ensure spot.id is populated from Firestore document ID
                if spot?.id == nil {
                    spot?.id = doc.documentID
                    FeedDiagnostics.logExclusion(reason: "nil_id_fixed", source: "FeedCandidateService.fetchTrending", spot: spot!)
                }
                return spot
            }
            return Page(items: items, last: snap.documents.last)
        } catch {
            // Missing composite index or other failure: gracefully fall back to createdAt desc
            SpotLogger.log(FeedCandidateServiceLogs.trendingQueryFallback, details: ["error": error.localizedDescription])
            var q: Query = db.collection("spots").order(by: "createdAt", descending: true).limit(to: pageSize)
            if let last { q = q.start(afterDocument: last) }
            let snap = try await q.getDocuments()
            let items = snap.documents.compactMap { doc in
                var spot = try? doc.data(as: Spot.self)
                // Ensure spot.id is populated from Firestore document ID
                if spot?.id == nil {
                    spot?.id = doc.documentID
                    FeedDiagnostics.logExclusion(reason: "nil_id_fixed", source: "FeedCandidateService.fetchTrending_fallback", spot: spot!)
                }
                return spot
            }
            return Page(items: items, last: snap.documents.last)
        }
    }

    // MARK: - Followees recent (chunked where-in)
    struct FolloweesPage { let items: [Spot]; let lastByChunk: [Int: DocumentSnapshot?] }

    func fetchFolloweesRecent(followeeIds: [String], lastByChunk: [Int: DocumentSnapshot?] = [:]) async throws -> FolloweesPage {
        guard !followeeIds.isEmpty else { return FolloweesPage(items: [], lastByChunk: [:]) }

        // Firestore where-in supports up to 10 ids. Chunk and merge client-side.
        let chunks: [[String]] = stride(from: 0, to: followeeIds.count, by: 10).map {
            Array(followeeIds[$0..<min($0+10, followeeIds.count)])
        }

        var results: [Spot] = []
        var newCursors: [Int: DocumentSnapshot?] = [:]

        try await withThrowingTaskGroup(of: (Int, QuerySnapshot).self) { group in
            for (idx, ids) in chunks.enumerated() {
                group.addTask {
                    var q: Query = self.db.collection("spots")
                        .whereField("userId", in: ids)
                        .order(by: "createdAt", descending: true)
                        .limit(to: self.pageSize)
                    if let last = lastByChunk[idx] ?? nil { q = q.start(afterDocument: last) }
                    let snap = try await q.getDocuments()
                    return (idx, snap)
                }
            }

            for try await (idx, snap) in group {
                let items = snap.documents.compactMap { doc -> Spot? in
                    var spot = try? doc.data(as: Spot.self)
                    if spot?.id == nil { spot?.id = doc.documentID }
                    return spot
                }
                results.append(contentsOf: items)
                newCursors[idx] = snap.documents.last
            }
        }

        // Sort merged results by createdAt desc (server already sorted per chunk)
        results.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return FolloweesPage(items: results, lastByChunk: newCursors)
    }
}
