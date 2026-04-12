//
//  ProfileViewModel.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation
import FirebaseFirestore

class ProfileViewModel: ObservableObject {
    @Published var username: String?
    @Published var profileImageURL: String?
    @Published var spots: [Spot] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isPrivateProfile = false
    @Published var isProProfile = false
    @Published var isFollowingUser = false
    @Published var hasRequestedFollow = false
    @Published var canViewContent = true
    @Published var deletingSpotIds: Set<String> = []
    @Published var followRequestsCount: Int = 0

    private var loadTask: Task<Void, Never>?
    private var followReqListener: ListenerRegistration?
    private var lastLoadedUserId: String?
    private var hasLoaded = false

    deinit {
        loadTask?.cancel()
        stopFollowRequestsListener()
    }

    /// Load profile for the given user (nil = current user). Uses ProfileService.
    func loadUser(userId: String?, forceReload: Bool = false) async {
        guard !isLoading else { return }
        if !forceReload, hasLoaded, lastLoadedUserId == userId { return }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        loadTask?.cancel()
        loadTask = Task {
            do {
                let data = try await ProfileService.fetchProfile(for: userId)
                await MainActor.run {
                    self.username = data.username
                    self.profileImageURL = data.profileImageURL
                    self.spots = data.spots
                    self.isPrivateProfile = data.isPrivate
                    self.isProProfile = data.isPro
                    self.isFollowingUser = data.isFollowing
                    self.hasRequestedFollow = data.hasRequested
                    self.canViewContent = data.canView
                    self.lastLoadedUserId = userId
                    self.hasLoaded = true
                    self.isLoading = false
                }
                SpotLogger.log(ProfileViewModelLogs.profileLoaded, details: ["username": data.username])
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
                SpotLogger.log(ProfileViewModelLogs.loadUserFailed, details: ["error": error.localizedDescription])
            }
        }
        await loadTask?.value
    }

    /// Delete spot with optimistic update; rollback on failure.
    @MainActor
    func deleteSpot(_ spot: Spot) async {
        guard let id = spot.id else { return }
        if deletingSpotIds.contains(id) { return }
        deletingSpotIds.insert(id)
        let prevSpots = spots
        spots.removeAll { $0.id == id }

        do {
            try await SpotService.shared.deleteSpot(spot)
            deletingSpotIds.remove(id)
        } catch {
            SpotLogger.log(ProfileViewModelLogs.profileDeleteFailed, details: ["error": error.localizedDescription])
            spots = prevSpots
            deletingSpotIds.remove(id)
        }
    }

    /// Start listening to follow-request count for own private profile.
    func startFollowRequestsListener(ownUserId: String?) {
        stopFollowRequestsListener()
        guard let uid = ownUserId else { return }
        followReqListener = FollowRequestsService.shared.listenPendingCount(for: uid) { [weak self] n in
            DispatchQueue.main.async {
                self?.followRequestsCount = n
            }
        }
    }

    func stopFollowRequestsListener() {
        followReqListener?.remove()
        followReqListener = nil
    }

    func follow(targetUserId: String) {
        isFollowingUser = true
        UserSpotService.shared.follow(userId: targetUserId) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure = result { self?.isFollowingUser = false }
            }
        }
    }

    func unfollow(targetUserId: String) {
        isFollowingUser = false
        UserSpotService.shared.unfollow(userId: targetUserId) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure = result { self?.isFollowingUser = true }
            }
        }
    }

    func requestFollow(targetUserId: String) {
        hasRequestedFollow = true
        UserSpotService.shared.requestFollow(userId: targetUserId) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure = result { self?.hasRequestedFollow = false }
            }
        }
    }

    func cancelFollowRequest(targetUserId: String) {
        hasRequestedFollow = false
        UserSpotService.shared.cancelFollowRequest(userId: targetUserId) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure = result { self?.hasRequestedFollow = true }
            }
        }
    }

    // MARK: - Legacy (for existing callers that use current-user-only profile)
    var user: User? {
        guard let id = lastLoadedUserId else { return nil }
        return User(
            id: id,
            username: username ?? "User",
            profileImageURL: profileImageURL,
            isPrivate: isPrivateProfile,
            isCurrentUser: true,
            vibeStats: nil,
            createdAt: nil,
            blockedUsers: nil,
            customVibeTags: nil
        )
    }

    func loadUserProfile() async {
        await loadUser(userId: nil)
    }

    // MARK: - Preview Data
    static let previewViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.username = "Eddie Wynman"
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
        vm.username = "John Doe"
        vm.profileImageURL = "https://example.com/profile.jpg"
        vm.isPrivateProfile = false
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
        vm.username = "Private User"
        vm.isPrivateProfile = true
        return vm
    }()

    static let previewEmptyViewModel: ProfileViewModel = {
        let vm = ProfileViewModel()
        vm.username = "New User"
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
