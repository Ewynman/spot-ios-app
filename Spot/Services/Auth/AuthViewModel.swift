//
//  AuthViewModel.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = true
    @Published var userId: String? = nil
    @Published var likedSpots: [String] = []
    @Published var bookmarkedSpots: [String] = []

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        listenToAuthState()
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func listenToAuthState() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                SpotLogger.debug("Auth state changed - user signed in: \(user.uid)")
                DispatchQueue.main.async {
                    self?.userId = user.uid
                }
                // Verify user exists in Firestore
                AuthService.shared.verifyUserExists { exists in
                    DispatchQueue.main.async {
                        self?.isAuthenticated = exists
                        self?.isLoading = false
                        if exists {
                            self?.refreshUserSpotLists()
                        }
                        if !exists {
                            SpotLogger.warning("User authenticated but no Firestore document exists")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    SpotLogger.debug("Auth state changed - no user")
                    self?.userId = nil
                    self?.isAuthenticated = false
                    self?.isLoading = false
                    self?.likedSpots = []
                    self?.bookmarkedSpots = []
                }
            }
        }
    }

    func signUp(email: String, password: String, username: String, profileImageURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.signUp(email: email, password: password, username: username, profileImageURL: profileImageURL) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.signIn(email: email, password: password) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func signOut() {
        do {
            try AuthService.shared.signOut()
            isAuthenticated = false
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
        }
    }

    func refreshUserSpotLists() {
        guard let userId = userId else { return }
        UserSpotService.shared.fetchUserSpotLists { [weak self] liked, bookmarked in
            DispatchQueue.main.async {
                self?.likedSpots = liked
                self?.bookmarkedSpots = bookmarked
            }
        }
    }

    func likeSpot(_ spotId: String) {
        UserSpotService.shared.likeSpot(spotId: spotId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    if !(self?.likedSpots.contains(spotId) ?? false) {
                        self?.likedSpots.append(spotId)
                    }
                }
            }
        }
    }
    func unlikeSpot(_ spotId: String) {
        UserSpotService.shared.unlikeSpot(spotId: spotId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.likedSpots.removeAll { $0 == spotId }
                }
            }
        }
    }
    func bookmarkSpot(_ spotId: String) {
        UserSpotService.shared.bookmarkSpot(spotId: spotId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    if !(self?.bookmarkedSpots.contains(spotId) ?? false) {
                        self?.bookmarkedSpots.append(spotId)
                    }
                }
            }
        }
    }
    func unbookmarkSpot(_ spotId: String) {
        UserSpotService.shared.unbookmarkSpot(spotId: spotId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.bookmarkedSpots.removeAll { $0 == spotId }
                }
            }
        }
    }
}
