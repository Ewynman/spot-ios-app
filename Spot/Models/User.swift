import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    var username: String
    var profileImageURL: String?
    var isPrivate: Bool
    var isCurrentUser: Bool
    var vibeStats: [String: Int]?
    var createdAt: Date?
    var blockedUsers: [String]?
    
    // Preview data
    static let previewUser = User(
        id: "preview123",
        username: "Eddie Wynman",
        profileImageURL: nil,
        isPrivate: false,
        isCurrentUser: true,
        vibeStats: [
            "Chill Spot": 5,
            "Hidden Gem": 3,
            "Photo Op": 2
        ],
        createdAt: Date(),
        blockedUsers: []
    )
} 
