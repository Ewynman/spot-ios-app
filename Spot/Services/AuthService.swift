//
//  AuthService.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

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

    func signUp(email: String, password: String, username: String, profileImageURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
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
                "profileImageURL": profileImageURL,
                "createdAt": FieldValue.serverTimestamp()
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
}
