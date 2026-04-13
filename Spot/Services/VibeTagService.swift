import Foundation
import FirebaseFirestore

final class VibeTagService {
    static let shared = VibeTagService()
    private init() {}

    private let db = Firestore.firestore()

    // Ensures a global vibe tag exists in the `vibeTags` collection.
    // Returns the document ID of the existing or newly created tag.
    @discardableResult
    func ensureTagExists(name rawName: String) async throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = name.lowercased()

        // Check for existing tag by lowercase name to avoid duplicates
        let existing = try await db.collection("vibeTags")
            .whereField("name_lower", isEqualTo: lower)
            .limit(to: 1)
            .getDocuments()
        if let doc = existing.documents.first {
            return doc.documentID
        }

        // Create new tag
        let data: [String: Any] = [
            "name": name,
            "name_lower": lower,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let ref = try await db.collection("vibeTags").addDocument(data: data)
        return ref.documentID
    }

    // Convenience: ensure tag exists globally and attach to user's customVibeTags array
    func ensureExistsAndAttachToUser(name: String, userId: String?) async {
        guard let userId = userId else { return }
        do {
            _ = try await ensureTagExists(name: name)
            try await db.collection("users").document(userId).setData([
                "customVibeTags": FieldValue.arrayUnion([name])
            ], merge: true)
            SpotLogger.log(VibeTagServiceLogs.vibeTagSaved, details: ["name": name])
        } catch {
            SpotLogger.log(VibeTagServiceLogs.savingVibeTagFailed, details: ["error": error.localizedDescription])
        }
    }

    func fetchAll(limit: Int = 1000) async -> [VibeTag] {
        do {
            let snap = try await db.collection("vibeTags")
                .order(by: "name_lower")
                .limit(to: limit)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: VibeTag.self) }
        } catch {
            SpotLogger.log(VibeTagServiceLogs.fetchVibeTagsFailed, details: ["error": error.localizedDescription])
            return []
        }
    }
}
