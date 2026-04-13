//
//  TokenService.swift
//  Spot
//
//  Created by Edward Wynman on 1/12/26.
//

import Foundation
import FirebaseAuth
import Security

class TokenService {
    static let shared = TokenService()

    private let tokenKey = "com.spotapp.spot.firebaseToken"
    private let expirationKey = "com.spotapp.spot.tokenExpiration"
    private let tokenExpirationHours: TimeInterval = 24 // 24 hours

    private init() {}

    // MARK: - Token Management

    /// Get a valid Firebase auth token, refreshing if necessary
    func getToken(completion: @escaping (Result<String, Error>) -> Void) {
        // Check if we have a cached token that's still valid
        if let cachedToken = getCachedToken(), !isTokenExpired() {
            SpotLogger.log(TokenServiceLogs.usingCachedToken)
            completion(.success(cachedToken))
            return
        }

        // Get fresh token from Firebase
        getFreshToken(completion: completion)
    }

    /// Force refresh the token
    func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
        SpotLogger.log(TokenServiceLogs.forcingTokenRefresh)
        getFreshToken(completion: completion)
    }

    /// Clear stored tokens (useful for logout)
    func clearTokens() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: expirationKey)
        SpotLogger.log(TokenServiceLogs.clearedStoredTokens)
    }

    // MARK: - Private Methods

    private func getFreshToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            let error = NSError(domain: "TokenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
            SpotLogger.log(TokenServiceLogs.noAuthenticatedUser)
            completion(.failure(error))
            return
        }

        currentUser.getIDToken { [weak self] token, error in
            if let error = error {
                SpotLogger.log(TokenServiceLogs.failedToGetIdToken, details: ["error": error.localizedDescription])
                completion(.failure(error))
                return
            }

            guard let token = token else {
                let error = NSError(domain: "TokenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No token received"])
                SpotLogger.log(TokenServiceLogs.noTokenReceived)
                completion(.failure(error))
                return
            }

            // Cache the token with expiration
            self?.cacheToken(token)
            SpotLogger.log(TokenServiceLogs.gotFreshToken)
            completion(.success(token))
        }
    }

    private func cacheToken(_ token: String) {
        let expirationDate = Date().addingTimeInterval(tokenExpirationHours * 3600)

        saveToKeychain(key: tokenKey, value: token)
        saveToKeychain(key: expirationKey, value: String(expirationDate.timeIntervalSince1970))
    }

    private func getCachedToken() -> String? {
        return getFromKeychain(key: tokenKey)
    }

    private func isTokenExpired() -> Bool {
        guard let expirationString = getFromKeychain(key: expirationKey),
              let expirationTimeInterval = TimeInterval(expirationString) else {
            return true // Consider expired if we can't read expiration
        }

        let expirationDate = Date(timeIntervalSince1970: expirationTimeInterval)
        return Date() >= expirationDate
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing item if it exists
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            SpotLogger.log(TokenServiceLogs.failedToSaveToKeychain, details: ["key": key, "status": status])
        }
    }

    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) {
            return string
        }

        return nil
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}