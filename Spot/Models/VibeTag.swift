import Foundation
import FirebaseFirestore

struct VibeTag: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let name: String
    let name_lower: String?
    let createdAt: Date?
}
