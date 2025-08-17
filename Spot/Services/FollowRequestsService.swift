import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FollowRequest: Identifiable, Hashable {
    let id: String // requesterUid
    let requesterUid: String
    let username: String?
    let photoURL: String?
    let createdAt: Date?
}

final class FollowRequestsService {
    static let shared = FollowRequestsService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: Count Listener
    func listenPendingCount(for targetUid: String, onChange: @escaping (Int) -> Void) -> ListenerRegistration {
        SpotLogger.debug("FollowRequestsService: start count listener for target=\(targetUid)")
        return db.collection("users").document(targetUid).collection("followRequests")
            .addSnapshotListener { snapshot, _ in
                let count = snapshot?.documents.count ?? 0
                SpotLogger.info("Follow.Requests.Count n=\(count)")
                onChange(count)
            }
    }

    // MARK: Paged Fetch
    struct Page { let items: [FollowRequest]; let last: DocumentSnapshot? }

    func fetchPage(for targetUid: String, last: DocumentSnapshot? = nil, pageSize: Int = 24) async throws -> Page {
        var q: Query = db.collection("users").document(targetUid).collection("followRequests")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        if let last { q = q.start(afterDocument: last) }

        let snap = try await q.getDocuments()
        let items: [FollowRequest] = snap.documents.map { doc in
            let data = doc.data()
            return FollowRequest(
                id: doc.documentID,
                requesterUid: doc.documentID,
                username: data["username"] as? String,
                photoURL: data["photoURL"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
            )
        }
        return Page(items: items, last: snap.documents.last)
    }

    // MARK: Actions
    func accept(requesterUid: String, targetUid: String) async throws {
        SpotLogger.info("Follow.Request.Accepted requesterUid=\(requesterUid)")
        let batch = db.batch()

        // 1) Add to requester's following array (idempotent)
        let requesterRef = db.collection("users").document(requesterUid)
        batch.updateData(["following": FieldValue.arrayUnion([targetUid])], forDocument: requesterRef)

        // 2) Optional: create followers subcollection doc under target (idempotent)
        let followerRef = db.collection("users").document(targetUid).collection("followers").document(requesterUid)
        batch.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: followerRef, merge: true)

        // 3) Cleanup: delete follow request
        let reqRef = db.collection("users").document(targetUid).collection("followRequests").document(requesterUid)
        batch.deleteDocument(reqRef)

        try await batch.commit()

        // Local: invalidate privacy cache so future checks reload
        await AuthorPrivacyCache.shared.invalidate(authorId: requesterUid)
    }

    func deny(requesterUid: String, targetUid: String) async throws {
        SpotLogger.info("Follow.Request.Denied requesterUid=\(requesterUid)")
        let reqRef = db.collection("users").document(targetUid).collection("followRequests").document(requesterUid)
        try await reqRef.delete()
    }
}


