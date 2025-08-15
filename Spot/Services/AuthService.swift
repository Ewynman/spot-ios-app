//
//  AuthService.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

class AuthService {
    static let shared = AuthService()
    private init() {}
    
    // MARK: - Sign Up with Email-in-Use Handling
    
    func signUp(email: String, password: String) async throws -> AuthResult {
        // Trim and lowercase email
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        do {
            let result = try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
            
            // Create user document
            try await createUserDocument(for: result.user)
            
            return .success(result.user)
        } catch let error as NSError {
            if error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                return try await handleEmailInUse(email: cleanEmail)
            } else {
                throw error
            }
        }
    }
    
    private func handleEmailInUse(email: String) async throws -> AuthResult {
        // Check what providers are available for this email
        let providers = try await Auth.auth().fetchSignInMethods(forEmail: email)
        
        SpotLogger.info("\(Constants.Analytics.authEmailInUse) providers=\(providers) action=detected")
        
        if providers.contains("password") {
            // Account exists with password
            return .emailInUse(.passwordAccount)
        } else if providers.contains(where: { $0.contains("apple.com") || $0.contains("google.com") }) {
            // Account exists with federated provider
            let provider = providers.first { $0.contains("apple.com") || $0.contains("google.com") } ?? "unknown"
            return .emailInUse(.federatedAccount(provider))
        } else {
            // Empty providers (rare race condition or wrong project)
            SpotLogger.error("\(Constants.Analytics.authEmailInUse) providers=\(providers) action=inconsistentState")
            return .emailInUse(.inconsistentState)
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async throws -> AuthResult {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        do {
            let result = try await Auth.auth().signIn(withEmail: cleanEmail, password: password)
            return .success(result.user)
        } catch {
            throw error
        }
    }
    
    // MARK: - Password Reset
    
    func resetPassword(email: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await Auth.auth().sendPasswordReset(withEmail: cleanEmail)
        SpotLogger.info("\(Constants.Analytics.authEmailInUse) action=reset")
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    // MARK: - User Document Creation
    
    private func createUserDocument(for user: FirebaseAuth.User) async throws {
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "username": user.email?.components(separatedBy: "@").first ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "isPrivate": false,
            "isVerified": false,
            "following": [],
            "requestedFollows": [],
            "blockedUsers": [],
            "likedSpots": [],
            "bookmarkedSpots": []
        ]
        
        try await Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .setData(userData)
    }

    // MARK: - Legacy/Callback API (to satisfy existing callers)

    /// Verify Firestore user document exists for current auth user
    func verifyUserExists(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            SpotLogger.debug("AuthService.verifyUserExists: no current user")
            completion(false)
            return
        }
        SpotLogger.debug("AuthService.verifyUserExists: checking uid=\(uid)")
        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                SpotLogger.error("verifyUserExists error: \(error.localizedDescription)")
                completion(false)
                return
            }
            let exists = snapshot?.exists ?? false
            if !exists {
                SpotLogger.warning("verifyUserExists: missing Firestore user doc; signing out")
                try? Auth.auth().signOut()
            }
            completion(exists)
        }
    }

    /// Completion-style sign up used by existing UI
    func signUp(email: String, password: String, username: String, profileImageURL: String, isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Auth.auth().createUser(withEmail: cleanEmail, password: password) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let user = result?.user else {
                completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user"])) )
                return
            }
            let userData: [String: Any] = [
                "email": cleanEmail,
                "username": username,
                "profileImageURL": profileImageURL,
                "createdAt": FieldValue.serverTimestamp(),
                "isPrivate": isPrivate,
                "isVerified": false,
                "following": [],
                "requestedFollows": [],
                "blockedUsers": [],
                "likedSpots": [],
                "bookmarkedSpots": []
            ]
            Firestore.firestore().collection("users").document(user.uid).setData(userData) { err in
                if let err = err { completion(.failure(err)) } else { completion(.success(())) }
            }
        }
    }

    /// Completion-style sign in used by existing UI
    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Auth.auth().signIn(withEmail: cleanEmail, password: password) { _, error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    // MARK: - Reauthentication / Account management (callback style for existing VM)

    func reauthenticate(withPassword password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])) )
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { _, error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func updateEmail(_ newEmail: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])) )
            return
        }
        user.updateEmail(to: newEmail) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func updatePassword(_ newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])) )
            return
        }
        user.updatePassword(to: newPassword) { error in
            if let error = error { completion(.failure(error)) } else { completion(.success(())) }
        }
    }

    func deleteAccount(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])) )
            return
        }
        let uid = user.uid
        // Re-authenticate then delete best-effort data and auth user
        reauthenticate(withPassword: password) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                let db = Firestore.firestore()
                let storage = Storage.storage()

                // Fetch user doc for possible profile image URL
                db.collection("users").document(uid).getDocument { userSnap, _ in
                    let profileURL = userSnap?.data()? ["profileImageURL"] as? String
                    
                    // Delete user's spots (docs + images) best effort
                    db.collection("spots").whereField("userId", isEqualTo: uid).getDocuments { snapshot, _ in
                        let group = DispatchGroup()
                        if let docs = snapshot?.documents {
                            for doc in docs {
                                let data = doc.data()
                                if let imageURL = data["imageURL"] as? String, !imageURL.isEmpty, let url = URL(string: imageURL), url.scheme == "https" {
                                    group.enter()
                                    storage.reference(forURL: imageURL).delete { _ in group.leave() }
                                }
                                group.enter()
                                doc.reference.delete { _ in group.leave() }
                            }
                        }
                        if let profileURL, let url = URL(string: profileURL), url.scheme == "https" {
                            group.enter()
                            storage.reference(forURL: profileURL).delete { _ in group.leave() }
                        }
                        group.notify(queue: .main) {
                            // Delete user document
                            db.collection("users").document(uid).delete { _ in
                                user.delete { err in
                                    if let err = err { completion(.failure(err)) } else { completion(.success(())) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Debug Functions (DEBUG only)
    
    #if DEBUG
    /// Delete Auth user by email (DEBUG only)
    func deleteAuthUserByEmail(_ email: String) async throws {
        SpotLogger.info("\(Constants.Analytics.authDeleteByEmail).requested email=\(email)")
        
        // This would call a Cloud Function in production
        // For now, just log the request
        SpotLogger.warning("AuthService: deleteAuthUserByEmail called - implement Cloud Function")
        
        // In production, this would be:
        // let functions = Functions.functions()
        // let data = ["email": email]
        // let result = try await functions.httpsCallable("deleteAuthUserByEmail").call(data)
        
        SpotLogger.info("\(Constants.Analytics.authDeleteByEmail).result=ok")
    }
    #endif
}

// MARK: - Auth Result Types

enum AuthResult {
    case success(FirebaseAuth.User)
    case emailInUse(EmailInUseType)
}

enum EmailInUseType {
    case passwordAccount
    case federatedAccount(String)
    case inconsistentState
    
    var message: String {
        switch self {
        case .passwordAccount:
            return "An account with this email already exists. Please sign in or reset your password."
        case .federatedAccount(let provider):
            let providerName = provider.contains("apple.com") ? "Apple" : "Google"
            return "This email is already associated with a \(providerName) account. Please continue with \(providerName) or use a different email."
        case .inconsistentState:
            return "There was an issue with this email. Please try again or use a different email."
        }
    }
    
    var suggestedActions: [String] {
        switch self {
        case .passwordAccount:
            return ["Sign In", "Forgot Password", "Use Different Email"]
        case .federatedAccount(let provider):
            let providerName = provider.contains("apple.com") ? "Apple" : "Google"
            return ["Continue with \(providerName)", "Use Different Email"]
        case .inconsistentState:
            return ["Try Again", "Use Different Email"]
        }
    }
}
