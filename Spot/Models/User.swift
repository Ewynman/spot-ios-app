import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    let username: String
    let profileImageURL: String?
    let isPrivate: Bool
    var isCurrentUser: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case profileImageURL
        case isPrivate
        case isCurrentUser
    }
}

// MARK: - Preview Helper
extension User {
    static let previewUser = User(
        id: "preview123",
        username: "Eddie Wynman",
        profileImageURL: nil,
        isPrivate: false,
        isCurrentUser: true
    )
    
    static let previewOtherUser = User(
        id: "other123",
        username: "John Doe",
        profileImageURL: "https://example.com/profile.jpg",
        isPrivate: true,
        isCurrentUser: false
    )
} 
