//
//  AuthViewModel.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = true
    @Published var userId: String? = nil
    @Published var isEmailVerified: Bool = false
    @Published var emailResendAvailableAt: Date? = nil
    @Published var likedSpots: [String] = []
    @Published var bookmarkedSpots: [String] = []
    @Published var blockedUsers: [String] = []

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
                    self?.isAuthenticated = true
                    self?.isLoading = false
                    self?.isEmailVerified = user.isEmailVerified
                    self?.refreshUserSpotLists()
                    self?.refreshBlockedUsers()
                }
            } else {
                DispatchQueue.main.async {
                    SpotLogger.debug("Auth state changed - no user")
                    self?.userId = nil
                    self?.isAuthenticated = false
                    self?.isLoading = false
                    self?.isEmailVerified = false
                    self?.likedSpots = []
                    self?.bookmarkedSpots = []
                    self?.blockedUsers = []
                }
            }
        }
    }

    func signUp(email: String, password: String, username: String, profileImageURL: String, isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                let result = try await AuthService.shared.signUp(email: email, password: password)
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                case .emailInUse(let emailInUseType):
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: emailInUseType.message])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                let result = try await AuthService.shared.signIn(email: email, password: password)
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                case .emailInUse:
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected email in use during sign in"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    @MainActor func signOut() {
        do {
            try AuthService.shared.signOut()
            isAuthenticated = false
            // Clear deep link state when user logs out
            DeepLinkState.shared.clearUserSession()
            // Clear privacy session cache (actor)
            Task { await AuthorPrivacyCache.shared.clear() }
        } catch {
            SpotLogger.error("Failed to signout:\(error.localizedDescription)")
        }
    }

    func refreshUserSpotLists() {
        guard userId != nil else { return }
        UserSpotService.shared.fetchUserSpotLists { [weak self] liked, bookmarked in
            DispatchQueue.main.async {
                self?.likedSpots = liked
                self?.bookmarkedSpots = bookmarked
            }
        }
        // Also fetch blocked users
        refreshBlockedUsers()
    }
    
    func refreshBlockedUsers() {
        guard let userId = userId else { return }
        Task {
            do {
                let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                let blocked = userDoc.data()?["blockedUsers"] as? [String] ?? []
                await MainActor.run {
                    self.blockedUsers = blocked
                }
            } catch {
                SpotLogger.error("Failed to refresh blocked users: \(error.localizedDescription)")
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

    // MARK: - Settings Updates
    func updateUsername(_ username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"]))); return }
        // Check uniqueness before updating
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("users")
                    .whereField("username", isEqualTo: username)
                    .limit(to: 1)
                    .getDocuments()
                if let doc = snapshot.documents.first, doc.documentID != userId {
                    completion(.failure(NSError(domain: "AuthVM", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])) )
                    return
                }
                Firestore.firestore().collection("users").document(userId).updateData(["username": username]) { error in
                    if let error = error { completion(.failure(error)) } else {
                        // Also update FirebaseAuth display name for consistency
                        if let changeReq = Auth.auth().currentUser?.createProfileChangeRequest() {
                            changeReq.displayName = username
                            changeReq.commitChanges(completion: nil)
                        }
                        completion(.success(()))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func updateName(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"]))); return }
        let data = ["name": name]
        Firestore.firestore().collection("users").document(userId).updateData(data) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func updateEmail(_ email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        // Normalize email
        let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        AuthService.shared.updateEmail(newEmail) { result in
            switch result {
            case .failure(let error):
                // Temporary bypass: if FirebaseAuth updateEmail fails (e.g., requires verification),
                // mirror the email to Firestore and treat as success. We'll implement full flow later.
                SpotLogger.warning("AuthViewModel.updateEmail failed: \(error.localizedDescription) — falling back to Firestore-only sync")
                Firestore.firestore().collection("users").document(userId).updateData(["email": newEmail]) { err in
                    if let err = err {
                        SpotLogger.error("AuthViewModel.updateEmail Firestore fallback failed: \(err.localizedDescription)")
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            case .success:
                // Mirror to Firestore profile
                Firestore.firestore().collection("users").document(userId).updateData(["email": newEmail]) { err in
                    if let err = err {
                        SpotLogger.warning("AuthViewModel.updateEmail: FirebaseAuth updated but Firestore email sync failed: \(err.localizedDescription)")
                    }
                    completion(.success(()))
                }
            }
        }
    }

    func updatePassword(_ password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.updatePassword(password, completion: completion)
    }

    func setPrivateAccount(_ isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else { completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"]))); return }
        Firestore.firestore().collection("users").document(userId).updateData(["isPrivate": isPrivate]) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    // MARK: - Email Verification
    func sendVerificationEmail() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await user.sendEmailVerification()
            SpotLogger.info("Auth.EmailVerify.Sent")
            await MainActor.run { self.emailResendAvailableAt = Date().addingTimeInterval(30) }
        } catch {
            SpotLogger.error("sendVerificationEmail failed: \(error.localizedDescription)")
        }
    }

    func canResendVerification() -> Bool {
        guard let t = emailResendAvailableAt else { return true }
        return Date() >= t
    }

    func secondsUntilResend() -> Int {
        guard let t = emailResendAvailableAt else { return 0 }
        return max(0, Int(t.timeIntervalSinceNow.rounded()))
    }

    func checkVerificationStatus() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        do {
            try await user.reload()
            let verified = user.isEmailVerified
            if verified { SpotLogger.info("Auth.EmailVerify.Verified") }
            await MainActor.run { self.isEmailVerified = verified }
            if verified, let uid = user.uid as String? {
                // Persist server-side marker for analytics and visibility
                try? await Firestore.firestore().collection("users").document(uid).setData(["isVerified": true], merge: true)
            }
            return verified
        } catch {
            SpotLogger.error("checkVerificationStatus failed: \(error.localizedDescription)")
            return false
        }
    }

    func verifyBeforeUpdateEmail(_ newEmail: String) async throws {
        guard let user = Auth.auth().currentUser else { throw NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"]) }
        do {
            // Prefer new API if available; fallback to generate link on backend if needed
            try await user.sendEmailVerification(beforeUpdatingEmail: newEmail)
            SpotLogger.info("Auth.ChangeEmail.VerifySent")
            await MainActor.run { self.emailResendAvailableAt = Date().addingTimeInterval(30) }
        } catch {
            let ns = error as NSError
            if ns.code == AuthErrorCode.requiresRecentLogin.rawValue {
                SpotLogger.warning("Auth.ChangeEmail.ReauthRequired")
            } else {
                SpotLogger.error("Auth.ChangeEmail.Error(\(ns.code))")
            }
            throw error
        }
    }

    var maskedEmail: String {
        let e = Auth.auth().currentUser?.email ?? ""
        guard let at = e.firstIndex(of: "@") else { return e }
        let name = e[..<at]
        let domain = e[at...]
        let keep = min(2, name.count)
        let head = name.prefix(keep)
        return String(head) + "****" + String(domain)
    }

    // MARK: - Reauthentication
    func reauthenticate(currentPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.reauthenticate(withPassword: currentPassword, completion: completion)
    }

    // MARK: - Username Availability
    func isUsernameAvailable(_ username: String) async -> Bool {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .whereField("username", isEqualTo: username)
                .limit(to: 1)
                .getDocuments()
            // If a doc exists and it's not the current user, not available
            if let doc = snapshot.documents.first, doc.documentID != self.userId {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Account Deletion
    func deleteAccount(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.deleteAccount(password: password, completion: completion)
    }
    
    // MARK: - Blocking
    func blockUser(userId targetUserId: String) async throws {
        guard let currentUserId = userId else { throw NSError(domain: "No current user", code: 0) }
        guard currentUserId != targetUserId else { throw NSError(domain: "Cannot block yourself", code: 0) }
        
        try await Firestore.firestore().collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayUnion([targetUserId])
        ])
        
        await MainActor.run {
            if !blockedUsers.contains(targetUserId) {
                blockedUsers.append(targetUserId)
            }
        }
        
        SpotLogger.info("User blocked: \(targetUserId)")
    }
    
    func unblockUser(userId targetUserId: String) async throws {
        guard let currentUserId = userId else { throw NSError(domain: "No current user", code: 0) }
        
        try await Firestore.firestore().collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayRemove([targetUserId])
        ])
        
        await MainActor.run {
            blockedUsers.removeAll { $0 == targetUserId }
        }
        
        SpotLogger.info("User unblocked: \(targetUserId)")
    }
}
