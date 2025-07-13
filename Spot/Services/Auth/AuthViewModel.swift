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
            DispatchQueue.main.async {
                self?.isAuthenticated = (user != nil)
                self?.isLoading = false
            }
        }
    }

    func signUp(email: String, password: String, username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthService.shared.signUp(email: email, password: password, username: username) { result in
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
}
