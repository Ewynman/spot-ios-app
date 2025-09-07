import Foundation
import FirebaseFirestore

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
            SpotLogger.warning("Trending query failed, falling back to createdAt desc: \(error.localizedDescription)")
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
}
