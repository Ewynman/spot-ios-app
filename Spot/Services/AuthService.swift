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

final class AuthService {
    static let shared = AuthService()
    private init() {}
    
    func verifyUserExists(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            SpotLogger.debug("No current user, skipping verification")
            completion(false)
            return
        }
        
        SpotLogger.debug("Verifying user document exists for uid: \(uid)")
        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                SpotLogger.error("Error verifying user: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            let exists = snapshot?.exists ?? false
            if !exists {
                SpotLogger.warning("User document not found in Firestore, signing out")
                try? Auth.auth().signOut()
            }
            completion(exists)
        }
    }

    func signUp(email: String, password: String, username: String, profileImageURL: String, isPrivate: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                print("🔥 Firebase signup error: \(error.localizedDescription)")
                print("🔥 Full error: \(error)")
                completion(.failure(error))
                return
            }

            guard let uid = result?.user.uid else {
                completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])))
                return
            }

            let userData: [String: Any] = [
                "email": email,
                "username": username,
                "username_lower": username.lowercased(),
                "profileImageURL": profileImageURL,
                "createdAt": FieldValue.serverTimestamp(),
                "isPrivate": isPrivate,
                // Initialize social arrays
                "following": [],
                "requestedFollows": [],
                // Initialize interaction arrays to avoid nil checks elsewhere
                "likedSpots": [],
                "bookmarkedSpots": []
            ]

            Firestore.firestore().collection("users").document(uid).setData(userData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Updates
    func updateEmail(_ newEmail: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])));
            return
        }
        user.sendEmailVerification() // optional: ensure user has verification capability
        user.updateEmail(to: newEmail) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func updatePassword(_ newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])));
            return
        }
        user.updatePassword(to: newPassword) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    // Re-authenticate using current user's email and provided password
    func reauthenticate(withPassword password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])));
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    // Delete account: reauth with password, delete Firestore user doc, then delete auth user
    func deleteAccount(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])));
            return
        }
        let uid = user.uid
        reauthenticate(withPassword: password) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                let db = Firestore.firestore()
                let storage = Storage.storage()

                // Fetch user doc for potential profile image URL
                db.collection("users").document(uid).getDocument { userSnap, _ in
                    let profileURL = userSnap?.data()? ["profileImageURL"] as? String

                    // Fetch and delete all spots for this user (docs + images)
                    db.collection("spots").whereField("userId", isEqualTo: uid).getDocuments { snapshot, _ in
                        let group = DispatchGroup()

                        if let docs = snapshot?.documents {
                            for doc in docs {
                                let data = doc.data()
                                if let imageURL = data["imageURL"] as? String, !imageURL.isEmpty {
                                    group.enter()
                                    let ref = storage.reference(forURL: imageURL)
                                    ref.delete { _ in
                                        group.leave()
                                    }
                                }

                                group.enter()
                                doc.reference.delete { _ in
                                    group.leave()
                                }
                            }
                        }

                        // Also delete profile image if present
                        if let profileURL, !profileURL.isEmpty {
                            group.enter()
                            let ref = storage.reference(forURL: profileURL)
                            ref.delete { _ in
                                group.leave()
                            }
                        }

                        group.notify(queue: .main) {
                            // Delete user document last
                            db.collection("users").document(uid).delete { _ in
                                // Finally, delete auth user
                                user.delete { error in
                                    if let error = error {
                                        completion(.failure(error))
                                    } else {
                                        completion(.success(()))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
