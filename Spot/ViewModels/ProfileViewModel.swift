import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation // Added for geocoding

class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var spots: [Spot] = []
    @Published var isLoading = false
    @Published var error: Error?
    private var loadTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
    }
    
    func loadUserProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        loadTask?.cancel()
        loadTask = Task {
            do {
                let docRef = Firestore.firestore().collection("users").document(userId)
                let snapshot = try await docRef.getDocument()
                
                guard let data = snapshot.data() else {
                    await MainActor.run {
                        self.isLoading = false
                        self.error = ProfileError.userNotFound
                    }
                    return
                }
                
                let username = data["username"] as? String ?? "User"
                let profileImageURL = data["profileImageURL"] as? String
                let vibeStats = data["vibeStats"] as? [String: Int]
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                
                let user = User(
                    id: userId,
                    username: username,
                    profileImageURL: profileImageURL,
                    isPrivate: false,
                    isCurrentUser: true,
                    vibeStats: vibeStats,
                    createdAt: createdAt
                )
                
                await MainActor.run {
                    self.user = user
                    self.isLoading = false
                }
                
                SpotLogger.info("Loaded profile for user: \(username)")
                await loadUserSpots()
            } catch {
                SpotLogger.error("Failed to load user profile: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadUserSpots() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        loadTask?.cancel()
        loadTask = Task {
            do {
                let query = Firestore.firestore()
                    .collection("spots")
                    .whereField("userId", isEqualTo: userId)
                    .order(by: "createdAt", descending: true)
                
                let snapshot = try await query.getDocuments()
                
                let spots = try await withThrowingTaskGroup(of: Spot?.self) { group in
                    for document in snapshot.documents {
                        group.addTask {
                            return try await Spot.fromDocument(document)
                        }
                    }
                    
                    var validSpots: [Spot] = []
                    for try await spot in group {
                        if let spot = spot {
                            validSpots.append(spot)
                        }
                    }
                    return validSpots
                }
                
                await MainActor.run {
                    self.spots = spots
                }
                
                SpotLogger.info("Loaded \(spots.count) spots for user: \(userId)")
            } catch {
                SpotLogger.error("Failed to load user spots: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
    
    func togglePrivateProfile() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let userRef = Firestore.firestore().collection("users").document(userId)
                let currentPrivacy = user?.isPrivate ?? false
                
                try await userRef.updateData([
                    "isPrivate": !currentPrivacy
                ])
                
                await MainActor.run {
                    // Create a new User instance with updated privacy
                    if var updatedUser = self.user {
                        updatedUser.isPrivate = !currentPrivacy
                        self.user = updatedUser
                    }
                }
                
                SpotLogger.info("Updated profile privacy: \(!currentPrivacy)")
            } catch {
                SpotLogger.error("Failed to toggle profile privacy: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
    
    func requestAccess() {
        guard let targetUserId = user?.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let requestData: [String: Any] = [
                    "fromUserId": currentUserId,
                    "toUserId": targetUserId,
                    "status": "pending",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                try await Firestore.firestore().collection("accessRequests").addDocument(data: requestData)
                SpotLogger.info("Sent access request to user: \(targetUserId)")
            } catch {
                SpotLogger.error("Failed to send access request: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
    
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
}

// MARK: - Error Types
extension ProfileViewModel {
    enum ProfileError: LocalizedError {
        case userNotFound
        case spotsFetchFailed
        case unauthorized
        case unknown
        case missingIndex
        
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
            case .missingIndex:
                return "Database index is being created. Please try again in a few minutes."
            }
        }
    }
} 
