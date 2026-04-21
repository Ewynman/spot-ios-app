import Foundation

struct VibeTag: Identifiable, Codable, Hashable {
    var id: String?
    let name: String
    let name_lower: String?
    let createdAt: Date?
}
