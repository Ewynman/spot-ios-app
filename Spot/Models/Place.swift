import Foundation
import FirebaseFirestore

struct Place: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var name_lower: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var createdAt: Date?
    var createdBy: String?
    var postsCount: Int?
}
