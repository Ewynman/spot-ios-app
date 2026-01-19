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
    @Published var userId: String?
    @Published var isEmailVerified: Bool = false
    @Published var emailResendAvailableAt: Date?
    @Published var likedSpots: [String] = []
    @Published var bookmarkedSpots: [String] = []
    @Published var blockedUsers: [String] = []
    @Published var isPro: Bool = false
    @Published var proUntil: Date? = nil
    @Published var customVibeTags: [String] = []

    private var handle: AuthStateDidChangeListenerHandle?
    private var userDocListener: ListenerRegistration?

    init() {
        listenToAuthState()
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private var previousUserId: String?
    
    private func listenToAuthState() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                SpotLogger.debug("Auth state changed - user signed in: \(user.uid)")
                DispatchQueue.main.async {
                    let isNewLogin = self?.previousUserId == nil && self?.userId == nil
                    self?.userId = user.uid
                    self?.isAuthenticated = true
                    self?.isLoading = false
                    self?.isEmailVerified = user.isEmailVerified
                    self?.isPro = false
                    self?.proUntil = nil
                    self?.customVibeTags = []
                    
                    // Set user ID for analytics
                    AnalyticsService.shared.setUserId(user.uid)
                    
                    // Track login if this is a new session
                    if isNewLogin {
                        AnalyticsService.shared.logEvent("user_login", parameters: [
                            "email_verified": user.isEmailVerified
                        ])
                    }
                    
                    self?.refreshUserSpotLists()
                    self?.refreshBlockedUsers()
                    self?.refreshUserFlags()
                    // On first login after a fresh install, trigger permission prompts once.
                    if FreshInstallDetector.shared.consumePromptPermissionsOnNextLoginFlag() {
                        SpotLogger.info("Perms.AutoPrompt reason=freshInstallLogin")
                        PermissionManager.shared.requestPermissionsIfNeeded()
                    }
                    self?.previousUserId = user.uid
                }
                // Live observe user flags (e.g., isPro, proUntil) without restart
                self?.userDocListener?.remove()
                self?.userDocListener = Firestore.firestore().collection("users").document(user.uid)
                    .addSnapshotListener { [weak self] snapshot, _ in
                        guard let data = snapshot?.data() else { return }
                        let vibes = data["customVibeTags"] as? [String] ?? []
                        
                        // Check proUntil timestamp (new method) or fallback to isPro boolean (backward compatibility)
                        let proUntilDate: Date?
                        if let timestamp = data["proUntil"] as? Timestamp {
                            proUntilDate = timestamp.dateValue()
                        } else if let timestamp = data["proUntil"] as? Date {
                            proUntilDate = timestamp
                        } else {
                            proUntilDate = nil
                        }
                        
                        // Compute isPro from proUntil (if date exists and is in future) or fallback to isPro boolean
                        let isProValue: Bool
                        if let proUntil = proUntilDate {
                            isProValue = proUntil > Date()
                        } else {
                            // Backward compatibility: check isPro boolean
                            isProValue = data["isPro"] as? Bool ?? false
                        }
                        
                        DispatchQueue.main.async {
                            self?.isPro = isProValue
                            self?.proUntil = proUntilDate
                            self?.customVibeTags = vibes
                        }
                    }
            } else {
                DispatchQueue.main.async {
                    SpotLogger.debug("Auth state changed - no user")
                    // Clear analytics user ID on sign out
                    AnalyticsService.shared.setUserId(nil)
                    
                    self?.userId = nil
                    self?.isAuthenticated = false
                    self?.isLoading = false
                    self?.isEmailVerified = false
                    self?.likedSpots = []
                    self?.bookmarkedSpots = []
                    self?.blockedUsers = []
                    self?.isPro = false
                    self?.proUntil = nil
                    self?.customVibeTags = []
                }
                self?.previousUserId = nil
                self?.userDocListener?.remove()
                self?.userDocListener = nil
            }
        }
    }

    func signUp(email: String, password: String, username: String, profileImageURL: String, isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.signUp(email: email, password: password) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let authResult):
                    switch authResult {
                    case .success:
                        completion(.success(()))
                    case .emailInUse(let emailInUseType):
                        completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: emailInUseType.message])))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.signIn(email: email, password: password) { (result: Result<AuthResult, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let authResult):
                    switch authResult {
                    case .success:
                        completion(.success(()))
                    case .emailInUse:
                        completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected email in use during sign in"])))
                    }
                case .failure(let error):
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

    // MARK: - User flags (Pro)
    func refreshUserFlags() {
        guard let userId = userId else { return }
        Task {
            do {
                let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
                let data = userDoc.data() ?? [:]
                let vibes = data["customVibeTags"] as? [String] ?? []
                
                // Check proUntil timestamp (new method) or fallback to isPro boolean (backward compatibility)
                var proUntilDate: Date? = nil
                if let timestamp = data["proUntil"] as? Timestamp {
                    proUntilDate = timestamp.dateValue()
                } else if let timestamp = data["proUntil"] as? Date {
                    proUntilDate = timestamp
                }
                
                // Compute isPro from proUntil (if date exists and is in future) or fallback to isPro boolean
                let isProValue: Bool
                if let proUntil = proUntilDate {
                    isProValue = proUntil > Date()
                } else {
                    // Backward compatibility: check isPro boolean
                    isProValue = data["isPro"] as? Bool ?? false
                }
                
                await MainActor.run {
                    self.isPro = isProValue
                    self.proUntil = proUntilDate
                    self.customVibeTags = vibes
                }
            } catch {
                SpotLogger.error("Failed to refresh user flags: \(error.localizedDescription)")
            }
        }
    }

    func setProActive(_ active: Bool) async {
        guard let userId = userId else { return }
        do {
            // For backward compatibility, still set isPro boolean
            // But prefer proUntil timestamp if available
            try await Firestore.firestore().collection("users").document(userId).setData(["isPro": active], merge: true)
            await MainActor.run { self.isPro = active }
            SpotLogger.info("Pro status updated", details: ["active": active])
        } catch {
            SpotLogger.error("Failed to set pro status: \(error.localizedDescription)")
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
        // Free users capped at 50 bookmarks
        if !isPro && bookmarkedSpots.count >= 50 {
            SpotLogger.info("Bookmark cap reached", details: ["cap": 50])
            NotificationCenter.default.post(name: .showPaywall, object: nil)
            return
        }
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

    // MARK: - Settings Updates (async Firestore)
    func updateUsername(_ username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        Task {
            do {
                // Check uniqueness
                let snapshot = try await Firestore.firestore()
                    .collection("users")
                    .whereField("username", isEqualTo: username)
                    .limit(to: 1)
                    .getDocuments()
                if let doc = snapshot.documents.first, doc.documentID != userId {
                    await MainActor.run {
                        completion(.failure(NSError(domain: "AuthVM", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])))
                    }
                    return
                }

                try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .updateData(["username": username])

                if let changeReq = Auth.auth().currentUser?.createProfileChangeRequest() {
                    changeReq.displayName = username
                    try? await commitProfileChange(changeReq)
                }

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func updateName(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .updateData(["name": name])
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func updateEmail(_ email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        AuthService.shared.updateEmail(newEmail) { result in
            switch result {
            case .failure(let error):
                // Fallback: mirror to Firestore only
                SpotLogger.debug(.auth, "Email update failed, falling back to Firestore-only sync", details: ["error": error.localizedDescription])
                Task {
                    do {
                        try await Firestore.firestore()
                            .collection("users")
                            .document(userId)
                            .updateData(["email": newEmail])
                        await MainActor.run { completion(.success(())) }
                    } catch {
                        SpotLogger.error("AuthViewModel.updateEmail Firestore fallback failed: \(error.localizedDescription)")
                        await MainActor.run { completion(.failure(error)) }
                    }
                }

            case .success:
                // Mirror to Firestore profile
                Task {
                    do {
                        try await Firestore.firestore()
                            .collection("users")
                            .document(userId)
                            .updateData(["email": newEmail])
                        await MainActor.run { completion(.success(())) }
                    } catch {
                        SpotLogger.debug(.auth, "FirebaseAuth updated but Firestore email sync failed", details: ["error": error.localizedDescription])
                        await MainActor.run { completion(.success(())) } // keep your original behavior
                    }
                }
            }
        }
    }

    func updatePassword(_ password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.updatePassword(password, completion: completion)
    }

    func setPrivateAccount(_ isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .updateData(["isPrivate": isPrivate])
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
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
                SpotLogger.debug(.auth, "Email change requires reauthentication")
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

// MARK: - Helper
private func commitProfileChange(_ changeReq: UserProfileChangeRequest) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        changeReq.commitChanges { error in
            if let error = error {
                cont.resume(throwing: error)
            } else {
                cont.resume(returning: ())
            }
        }
    }
}
