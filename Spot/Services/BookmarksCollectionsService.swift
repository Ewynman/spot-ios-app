import Foundation
import FirebaseFirestore
import FirebaseAuth

struct BookmarkCollection: Identifiable, Codable {
    var id: String
    var name: String
    var spotIds: [String]
    var createdAt: Date?
}

final class BookmarksCollectionsService {
    static let shared = BookmarksCollectionsService()
    private init() {}

    private var db: Firestore { Firestore.firestore() }

    private func uid() throws -> String {
        guard let id = Auth.auth().currentUser?.uid else { throw NSError(domain: "No user", code: 0) }
        return id
    }

    func listCollections() async throws -> [BookmarkCollection] {
        let userId = try uid()
        let snap = try await db.collection("users").document(userId).collection("collections").order(by: "createdAt", descending: true).getDocuments()
        return snap.documents.map { doc in
            let data = doc.data()
            return BookmarkCollection(
                id: doc.documentID,
                name: data["name"] as? String ?? "",
                spotIds: data["spotIds"] as? [String] ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    func createCollection(name: String) async throws -> String {
        let userId = try uid()
        let ref = db.collection("users").document(userId).collection("collections").document()
        try await ref.setData([
            "name": name,
            "spotIds": [],
            "createdAt": FieldValue.serverTimestamp()
        ])
        return ref.documentID
    }

    func addSpot(_ spotId: String, to collectionId: String) async throws {
        let userId = try uid()
        try await db.collection("users").document(userId).collection("collections").document(collectionId)
            .updateData(["spotIds": FieldValue.arrayUnion([spotId])])
    }

    func removeSpot(_ spotId: String, from collectionId: String) async throws {
        let userId = try uid()
        try await db.collection("users").document(userId).collection("collections").document(collectionId)
            .updateData(["spotIds": FieldValue.arrayRemove([spotId])])
    }
}
