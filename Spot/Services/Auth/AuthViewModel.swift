//
//  AuthViewModel.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Supabase
import AuthenticationServices

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = true
    @Published var userId: String?
    @Published var isEmailVerified: Bool = false
    /// True when signup finished without a session (email confirmation / OTP pending).
    @Published var awaitingEmailVerification: Bool = false
    @Published var verificationEmailMaskSource: String = ""
    @Published var emailResendAvailableAt: Date?
    @Published var likedSpots: [String] = []
    @Published var bookmarkedSpots: [String] = []
    @Published var blockedUsers: [String] = []
    @Published var isPro: Bool = false
    @Published var proUntil: Date? = nil
    @Published var customVibeTags: [String] = []

    private var supabaseAuthTask: Task<Void, Never>?

    init() {
        listenToSupabaseAuthState()
    }

    deinit {
        supabaseAuthTask?.cancel()
    }

    private var previousUserId: String?

    private func listenToSupabaseAuthState() {
        supabaseAuthTask = Task { @MainActor [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                self?.applySupabaseAuthChange(event: event, session: session)
            }
        }
    }

    @MainActor
    private func applySupabaseAuthChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let session else {
                clearSignedOutState()
                return
            }
            if session.isExpired {
                return
            }
            let user = session.user
            SpotLogger.log(AuthViewModelLogs.authStateSignedIn, details: ["uid": user.id.uuidString])

            let isNewLogin = previousUserId == nil && userId == nil
            userId = user.id.uuidString
            SpotAuthBridge.setSessionUser(id: user.id.uuidString, email: user.email, emailVerified: user.emailConfirmedAt != nil)
            isAuthenticated = true
            isLoading = false
            isEmailVerified = user.emailConfirmedAt != nil
            awaitingEmailVerification = false
            verificationEmailMaskSource = user.email ?? verificationEmailMaskSource

            AnalyticsService.shared.setUserId(user.id.uuidString)

            if isNewLogin {
                AnalyticsService.shared.logEvent("user_login", parameters: [
                    "email_verified": user.emailConfirmedAt != nil
                ])
            }

            refreshUserSpotLists()
            refreshBlockedUsers()
            refreshUserFlags()
            Task {
                await SupabaseUserService.shared.syncCurrentUser()
            }
            previousUserId = user.id.uuidString

            refreshUserFlags()
            refreshBlockedUsers()

        case .signedOut:
            SpotLogger.log(AuthViewModelLogs.authStateSignedOut)
            clearSignedOutState()

        case .passwordRecovery, .userDeleted, .mfaChallengeVerified:
            break
        }
    }

    @MainActor
    private func clearSignedOutState() {
        AnalyticsService.shared.setUserId(nil)
        SpotAuthBridge.setSessionUser(id: nil, email: nil)
        userId = nil
        isAuthenticated = false
        isLoading = false
        isEmailVerified = false
        awaitingEmailVerification = false
        verificationEmailMaskSource = ""
        likedSpots = []
        bookmarkedSpots = []
        blockedUsers = []
        isPro = false
        proUntil = nil
        customVibeTags = []
        previousUserId = nil
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

    /// Completes native Apple auth by exchanging the Apple identity token with Supabase.
    /// Optionally persists the full name into auth metadata when Apple provides it (first consent only).
    func signInWithApple(idToken: String, fullName: PersonNameComponents?) async throws {
        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken
            )
        )

        if let fullName {
            var parts: [String] = []
            if let given = fullName.givenName, !given.isEmpty { parts.append(given) }
            if let middle = fullName.middleName, !middle.isEmpty { parts.append(middle) }
            if let family = fullName.familyName, !family.isEmpty { parts.append(family) }

            if !parts.isEmpty {
                let full = parts.joined(separator: " ")
                try? await supabase.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(full),
                            "given_name": .string(fullName.givenName ?? ""),
                            "family_name": .string(fullName.familyName ?? "")
                        ]
                    )
                )
            }
        }

        await SupabaseUserService.shared.syncCurrentUser()
    }

    @MainActor func signOut() {
        Task {
            do {
                try await supabase.auth.signOut()
            } catch {
                SpotLogger.log(AuthViewModelLogs.signOutFailed, details: ["error": error.localizedDescription])
            }
            await MainActor.run {
                self.isAuthenticated = false
                DeepLinkState.shared.clearUserSession()
            }
            await AuthorPrivacyCache.shared.clear()
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
        guard let userId = userId, let uid = UUID(uuidString: userId) else { return }
        Task {
            do {
                struct Row: Decodable { let blocked_user_id: UUID }
                let rows: [Row] = try await supabase
                    .from("user_blocks")
                    .select("blocked_user_id")
                    .eq("blocker_id", value: uid)
                    .execute()
                    .value
                let blocked = rows.map { $0.blocked_user_id.uuidString }
                await MainActor.run {
                    self.blockedUsers = blocked
                }
            } catch {
                SpotLogger.log(AuthViewModelLogs.refreshBlockedUsersFailed, details: ["error": error.localizedDescription])
            }
        }
    }

    // MARK: - User flags (Pro)
    func refreshUserFlags() {
        guard let userId = userId, let uid = UUID(uuidString: userId) else { return }
        Task {
            do {
                struct FlagsRow: Decodable {
                    let is_pro: Bool
                    let pro_until: String?
                }
                let row: FlagsRow = try await supabase
                    .from("users")
                    .select("is_pro,pro_until")
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value

                let proUntilDate = SpotSupabaseRepository.parseTimestamptz(row.pro_until)
                let isProValue: Bool
                if let until = proUntilDate {
                    isProValue = until > Date()
                } else {
                    isProValue = row.is_pro
                }

                await MainActor.run {
                    self.isPro = isProValue
                    self.proUntil = proUntilDate
                    self.customVibeTags = []
                }
            } catch {
                SpotLogger.log(AuthViewModelLogs.refreshUserFlagsFailed, details: ["error": error.localizedDescription])
            }
        }
    }

    func setProActive(_ active: Bool, proUntil: Date? = nil) async {
        guard let userId, let uid = UUID(uuidString: userId) else { return }
        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let proUntilString: String? = {
                if active, let expiry = proUntil { return formatter.string(from: expiry) }
                if !active { return nil }
                return nil
            }()

            struct ProPatch: Encodable {
                let is_pro: Bool
                let pro_until: String?
            }

            try await supabase
                .from("users")
                .update(ProPatch(is_pro: active, pro_until: proUntilString))
                .eq("id", value: uid)
                .execute()

            await MainActor.run {
                self.isPro = active
                self.proUntil = active ? proUntil : nil
            }
            SpotLogger.log(AuthViewModelLogs.proStatusUpdated, details: ["active": active, "proUntil": proUntil?.description ?? "nil"])
        } catch {
            SpotLogger.log(AuthViewModelLogs.proStatusUpdateFailed, details: ["error": error.localizedDescription])
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
            SpotLogger.log(AuthViewModelLogs.bookmarkCapReached, details: ["cap": 50])
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

    // MARK: - Settings Updates (Supabase `public.users` + auth metadata)
    func updateUsername(_ username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId, let uid = UUID(uuidString: userId) else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLower = trimmed.lowercased()
        Task {
            do {
                struct NameRow: Decodable { let username_lower: String }
                let current: NameRow = try await supabase
                    .from("users")
                    .select("username_lower")
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value

                if newLower != current.username_lower {
                    let available = await isUsernameAvailable(trimmed)
                    if !available {
                        await MainActor.run {
                            completion(.failure(NSError(domain: "AuthVM", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])))
                        }
                        return
                    }
                }

                struct UserPatch: Encodable {
                    let username: String
                    let username_lower: String
                }
                try await supabase
                    .from("users")
                    .update(UserPatch(username: trimmed, username_lower: newLower))
                    .eq("id", value: uid)
                    .execute()

                try await supabase.auth.update(
                    user: UserAttributes(data: ["username": .string(trimmed)])
                )

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func updateName(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard userId != nil else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        Task {
            do {
                try await supabase.auth.update(
                    user: UserAttributes(data: ["full_name": .string(name)])
                )
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func updateEmail(_ email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId, let uid = UUID(uuidString: userId) else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        AuthService.shared.updateEmail(newEmail) { result in
            switch result {
            case .failure(let error):
                SpotLogger.log(AuthViewModelLogs.emailUpdateFallingBackToFirestore, details: ["error": error.localizedDescription])
                Task {
                    do {
                        struct EmailPatch: Encodable { let email: String }
                        try await supabase
                            .from("users")
                            .update(EmailPatch(email: newEmail))
                            .eq("id", value: uid)
                            .execute()
                        await MainActor.run { completion(.success(())) }
                    } catch {
                        SpotLogger.log(AuthViewModelLogs.emailUpdateFirestoreFallbackFailed, details: ["error": error.localizedDescription])
                        await MainActor.run { completion(.failure(error)) }
                    }
                }

            case .success:
                Task {
                    do {
                        struct EmailPatch: Encodable { let email: String }
                        try await supabase
                            .from("users")
                            .update(EmailPatch(email: newEmail))
                            .eq("id", value: uid)
                            .execute()
                        await MainActor.run { completion(.success(())) }
                    } catch {
                        SpotLogger.log(AuthViewModelLogs.firebaseAuthUpdatedFirestoreSyncFailed, details: ["error": error.localizedDescription])
                        await MainActor.run { completion(.success(())) }
                    }
                }
            }
        }
    }

    func updatePassword(_ password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await supabase.auth.update(user: UserAttributes(password: password))
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func setPrivateAccount(_ isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = userId, let uid = UUID(uuidString: userId) else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            return
        }
        Task {
            do {
                struct PrivPatch: Encodable { let is_private: Bool }
                try await supabase
                    .from("users")
                    .update(PrivPatch(is_private: isPrivate))
                    .eq("id", value: uid)
                    .execute()

                try await supabase.auth.update(
                    user: UserAttributes(data: ["is_private": .bool(isPrivate)])
                )

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Email verification (Supabase email OTP / signup)
    func beginEmailVerificationPending(email: String, avatar: UIImage?) {
        awaitingEmailVerification = true
        pendingVerificationEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        verificationEmailMaskSource = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pendingAvatarAfterVerification = avatar
    }

    func clearEmailVerificationPending() {
        awaitingEmailVerification = false
        pendingVerificationEmail = nil
        pendingAvatarAfterVerification = nil
    }

    /// Verifies the 6-digit code from the signup email, establishes the session, uploads pending avatar, syncs profile.
    func verifySignupEmailOTP(code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            throw NSError(domain: "AuthVM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Enter the 6-digit code from your email."])
        }
        guard let email = pendingVerificationEmail else {
            throw NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing signup email. Go back and sign up again."])
        }
        _ = try await supabase.auth.verifyOTP(email: email, token: trimmed, type: .signup)
        try await completePendingAvatarUploadIfNeeded()
        clearEmailVerificationPending()
        await SupabaseUserService.shared.syncCurrentUser()
        if let user = try? await supabase.auth.user() {
            await MainActor.run {
                self.isEmailVerified = user.emailConfirmedAt != nil
            }
        }
    }

    private func completePendingAvatarUploadIfNeeded() async throws {
        guard let image = pendingAvatarAfterVerification,
              let data = image.jpegData(compressionQuality: 0.7) else { return }
        let session = try await supabase.auth.session
        let url = try await SupabaseUserService.shared.uploadProfileAvatarJPEG(data, userId: session.user.id)
        struct AvatarPatch: Encodable { let profile_image_url: String }
        try await supabase
            .from("users")
            .update(AvatarPatch(profile_image_url: url))
            .eq("id", value: session.user.id)
            .execute()
    }

    private var pendingVerificationEmail: String?
    private var pendingAvatarAfterVerification: UIImage?

    func sendVerificationEmail() async {
        let email: String?
        if let pending = pendingVerificationEmail {
            email = pending
        } else {
            email = (try? await supabase.auth.session)?.user.email
        }
        guard let email, !email.isEmpty else { return }
        do {
            try await supabase.auth.resend(email: email, type: .signup)
            SpotLogger.log(AuthViewModelLogs.verificationEmailSent)
            await MainActor.run { self.emailResendAvailableAt = Date().addingTimeInterval(30) }
        } catch {
            SpotLogger.log(AuthViewModelLogs.sendVerificationEmailFailed, details: ["error": error.localizedDescription])
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
        do {
            let user = try await supabase.auth.user()
            let verified = user.emailConfirmedAt != nil
            if verified { SpotLogger.log(AuthViewModelLogs.emailVerified) }
            await MainActor.run { self.isEmailVerified = verified }
            if verified, let uidString = userId, let uid = UUID(uuidString: uidString) {
                struct VerifiedPatch: Encodable { let email_verified: Bool }
                try? await supabase
                    .from("users")
                    .update(VerifiedPatch(email_verified: true))
                    .eq("id", value: uid)
                    .execute()
            }
            return verified
        } catch {
            SpotLogger.log(AuthViewModelLogs.checkVerificationStatusFailed, details: ["error": error.localizedDescription])
            return false
        }
    }

    func verifyBeforeUpdateEmail(_ newEmail: String) async throws {
        do {
            try await supabase.auth.update(user: UserAttributes(email: newEmail))
            SpotLogger.log(AuthViewModelLogs.changeEmailVerifySent)
            await MainActor.run { self.emailResendAvailableAt = Date().addingTimeInterval(30) }
        } catch {
            SpotLogger.log(AuthViewModelLogs.changeEmailError, details: ["error": error.localizedDescription])
            throw error
        }
    }

    var maskedEmail: String {
        let e = verificationEmailMaskSource
        guard let at = e.firstIndex(of: "@") else { return e }
        let name = e[..<at]
        let domain = e[at...]
        let keep = min(2, name.count)
        let head = name.prefix(keep)
        return String(head) + "****" + String(domain)
    }

    // MARK: - Reauthentication
    func reauthenticate(currentPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Current password is required."])))
            return
        }
        Task {
            do {
                let user = try await supabase.auth.user()
                guard let email = user.email, !email.isEmpty else {
                    throw NSError(domain: "AuthVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing account email for reauthentication."])
                }
                _ = try await supabase.auth.signIn(email: email, password: trimmed)
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Username Availability
    func isUsernameAvailable(_ username: String) async -> Bool {
        struct Params: Encodable { let p_username: String }
        do {
            let available: Bool = try await supabase
                .rpc("is_username_available", params: Params(p_username: username))
                .execute()
                .value
            return available
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
        guard let currentUserId = userId,
              let blocker = UUID(uuidString: currentUserId),
              let blocked = UUID(uuidString: targetUserId)
        else { throw NSError(domain: "No current user", code: 0) }
        guard currentUserId != targetUserId else { throw NSError(domain: "Cannot block yourself", code: 0) }

        struct BlockInsert: Encodable {
            let blocker_id: UUID
            let blocked_user_id: UUID
        }
        try await supabase
            .from("user_blocks")
            .insert(BlockInsert(blocker_id: blocker, blocked_user_id: blocked))
            .execute()

        await MainActor.run {
            if !blockedUsers.contains(targetUserId) {
                blockedUsers.append(targetUserId)
            }
        }

        SpotLogger.log(AuthViewModelLogs.userBlocked, details: ["targetUserId": targetUserId])
    }

    func unblockUser(userId targetUserId: String) async throws {
        guard let currentUserId = userId,
              let blocker = UUID(uuidString: currentUserId),
              let blocked = UUID(uuidString: targetUserId)
        else { throw NSError(domain: "No current user", code: 0) }

        try await supabase
            .from("user_blocks")
            .delete()
            .eq("blocker_id", value: blocker)
            .eq("blocked_user_id", value: blocked)
            .execute()

        await MainActor.run {
            blockedUsers.removeAll { $0 == targetUserId }
        }

        SpotLogger.log(AuthViewModelLogs.userUnblocked, details: ["targetUserId": targetUserId])
    }
}

