//
//  SubscriptionWebService.swift
//  Spot
//
//  Created for web-based subscription flow
//

import Foundation
import UIKit
import SafariServices
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SubscriptionWebService {
    static let shared = SubscriptionWebService()
    private init() {}
    
    // Base URL for subscription website
    private let subscriptionBaseURL = "https://spotapp.online/subscribe"
    
    // Token expiration time (15 minutes)
    private let tokenExpirationMinutes: TimeInterval = 15
    
    /// Creates a secure session token in Firestore and opens subscription page with only the token
    func openSubscriptionPageForCurrentUser() {
        guard let user = Auth.auth().currentUser else {
            SpotLogger.error("SubscriptionWebService: No current user", details: [:])
            return
        }
        
        Task {
            do {
                // Fetch username from Firestore
                let userDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(user.uid)
                    .getDocument()
                
                let username = userDoc.data()?["username"] as? String
                
                // Create secure session token
                let sessionToken = UUID().uuidString
                let expirationDate = Date().addingTimeInterval(tokenExpirationMinutes * 60)
                
                // Store session data in Firestore (will be deleted after use or expiration)
                let sessionData: [String: Any] = [
                    "userId": user.uid,
                    "email": user.email ?? "",
                    "username": username ?? "",
                    "returnUrl": "spotapp://subscription/return",
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(date: expirationDate)
                ]
                
                try await Firestore.firestore()
                    .collection("subscriptionSessions")
                    .document(sessionToken)
                    .setData(sessionData)
                
                SpotLogger.info("SubscriptionWebService: Created secure session token", details: ["token": sessionToken, "userId": user.uid])
                
                // Build URL with only the token (no sensitive data)
                guard let url = buildSubscriptionURL(token: sessionToken) else {
                    SpotLogger.error("SubscriptionWebService: Failed to build subscription URL", details: ["token": sessionToken])
                    return
                }
                
                SpotLogger.info("SubscriptionWebService: Opening subscription page with secure token")
                
                // Open in Safari (external browser) so user can complete payment
                await MainActor.run {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if success {
                            SpotLogger.info("SubscriptionWebService: Successfully opened subscription page")
                        } else {
                            SpotLogger.error("SubscriptionWebService: Failed to open subscription page")
                        }
                    }
                }
                
                // Schedule cleanup of expired tokens (fire and forget)
                scheduleTokenCleanup(sessionToken: sessionToken, expirationDate: expirationDate)
                
            } catch {
                SpotLogger.error("SubscriptionWebService: Failed to create session token", details: ["error": error.localizedDescription])
            }
        }
    }
    
    /// Builds subscription URL with only the secure token (no sensitive data)
    private func buildSubscriptionURL(token: String) -> URL? {
        guard var components = URLComponents(string: subscriptionBaseURL) else {
            return nil
        }
        
        // Only pass the token - no user data in URL
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "returnUrl", value: "spotapp://subscription/return")
        ]
        
        return components.url
    }
    
    /// Schedules cleanup of the session token after expiration
    private func scheduleTokenCleanup(sessionToken: String, expirationDate: Date) {
        let delay = expirationDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task {
                do {
                    try await Firestore.firestore()
                        .collection("subscriptionSessions")
                        .document(sessionToken)
                        .delete()
                    SpotLogger.info("SubscriptionWebService: Cleaned up expired session token", details: ["token": sessionToken])
                } catch {
                    SpotLogger.error("SubscriptionWebService: Failed to cleanup expired token", details: ["token": sessionToken, "error": error.localizedDescription])
                }
            }
        }
    }
}
