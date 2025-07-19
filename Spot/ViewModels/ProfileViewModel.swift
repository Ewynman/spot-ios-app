import Foundation
import FirebaseFirestore
import FirebaseAuth

class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var spots: [Spot] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    // MARK: - Preview Data
    static let previewViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.user = User.previewUser
        vm.spots = [
            Spot(
                id: "spot1",
                userId: "preview123",
                username: "Eddie Wynman",
                userProfileImageURL: nil,
                imageURL: "https://example.com/spot1.jpg",
                caption: "Beautiful sunset",
                vibeTag: "Sunset Spot",
                latitude: 25.7617,
                longitude: -80.1918,
                locationName: "Miami Beach",
                likes: 10,
                isLiked: false,
                isSaved: true,
                createdAt: Date()
            ),
            Spot(
                id: "spot2",
                userId: "preview123",
                username: "Eddie Wynman",
                userProfileImageURL: nil,
                imageURL: "https://example.com/spot2.jpg",
                caption: "Ocean vibes",
                vibeTag: "Beach Spot",
                latitude: 25.7616,
                longitude: -80.1917,
                locationName: "South Beach",
                likes: 15,
                isLiked: true,
                isSaved: false,
                createdAt: Date()
            )
        ]
        return vm
    }()
    
    static let previewOtherUserViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.user = User(
            id: "other123",
            username: "John Doe",
            profileImageURL: "https://example.com/profile.jpg",
            isPrivate: false,
            isCurrentUser: false
        )
        vm.spots = [
            Spot(
                id: "spot3",
                userId: "other123",
                username: "John Doe",
                userProfileImageURL: "https://example.com/profile.jpg",
                imageURL: "https://example.com/spot3.jpg",
                caption: "City lights",
                vibeTag: "Night Spot",
                latitude: 25.7615,
                longitude: -80.1916,
                locationName: "Downtown Miami",
                likes: 20,
                isLiked: true,
                isSaved: true,
                createdAt: Date()
            )
        ]
        return vm
    }()
    
    static let previewPrivateViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.user = User(
            id: "private123",
            username: "Private User",
            profileImageURL: nil,
            isPrivate: true,
            isCurrentUser: false
        )
        return vm
    }()
    
    static let previewEmptyViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.user = User(
            id: "empty123",
            username: "New User",
            profileImageURL: nil,
            isPrivate: false,
            isCurrentUser: false
        )
        vm.spots = []
        return vm
    }()
    
    // MARK: - Methods for Firebase Integration (to be implemented)
    func loadUserProfile(userId: String? = nil) {
        // If userId is nil, load current user's profile
        // Otherwise load the specified user's profile
        // This will be implemented when we add Firebase
    }
    
    func loadUserSpots(userId: String? = nil) {
        // Load spots for the current profile
        // This will be implemented when we add Firebase
    }
    
    func togglePrivateProfile() {
        // Toggle the profile privacy setting
        // This will be implemented when we add Firebase
    }
    
    func requestAccess() {
        // Send access request to private profile
        // This will be implemented when we add Firebase
    }
}

// MARK: - Error Types
extension ProfileViewModel {
    enum ProfileError: LocalizedError {
        case userNotFound
        case spotsFetchFailed
        case unauthorized
        case unknown
        
        var errorDescription: String? {
            switch self {
            case .userNotFound:
                return "User not found"
            case .spotsFetchFailed:
                return "Failed to load spots"
            case .unauthorized:
                return "You don't have access to view this profile"
            case .unknown:
                return "An unknown error occurred"
            }
        }
    }
} 