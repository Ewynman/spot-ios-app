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
    private let subscriptionManageURL = "https://spotapp.online/manage-subscription"
    
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
                    "action": "subscribe",
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(date: expirationDate)
                ]
                
                try await Firestore.firestore()
                    .collection("subscriptionSessions")
                    .document(sessionToken)
                    .setData(sessionData)
                
                SpotLogger.info("SubscriptionWebService: Created secure session token", details: ["token": sessionToken, "userId": user.uid])
                
                // Build URL with token and userId (userId for redundancy)
                guard let url = buildSubscriptionURL(token: sessionToken, userId: user.uid) else {
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
    
    /// Opens the subscription management/cancellation page
    func openSubscriptionManagementPage() {
        guard let user = Auth.auth().currentUser else {
            SpotLogger.error("SubscriptionWebService: No current user for management", details: [:])
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
                
                // Create secure session token for management
                let sessionToken = UUID().uuidString
                let expirationDate = Date().addingTimeInterval(tokenExpirationMinutes * 60)
                
                // Store session data in Firestore
                let sessionData: [String: Any] = [
                    "userId": user.uid,
                    "email": user.email ?? "",
                    "username": username ?? "",
                    "returnUrl": "spotapp://subscription/return",
                    "action": "manage", // Indicates this is for management/cancellation
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(date: expirationDate)
                ]
                
                try await Firestore.firestore()
                    .collection("subscriptionSessions")
                    .document(sessionToken)
                    .setData(sessionData)
                
                SpotLogger.info("SubscriptionWebService: Created management session token", details: ["token": sessionToken, "userId": user.uid])
                
                // Build URL with token and userId (userId for redundancy)
                guard let url = buildManagementURL(token: sessionToken, userId: user.uid) else {
                    SpotLogger.error("SubscriptionWebService: Failed to build management URL", details: ["token": sessionToken])
                    return
                }
                
                SpotLogger.info("SubscriptionWebService: Opening subscription management page")
                
                // Open in Safari
                await MainActor.run {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if success {
                            SpotLogger.info("SubscriptionWebService: Successfully opened management page")
                        } else {
                            SpotLogger.error("SubscriptionWebService: Failed to open management page")
                        }
                    }
                }
                
                // Schedule cleanup
                scheduleTokenCleanup(sessionToken: sessionToken, expirationDate: expirationDate)
                
            } catch {
                SpotLogger.error("SubscriptionWebService: Failed to create management session token", details: ["error": error.localizedDescription])
            }
        }
    }
    
    /// Builds subscription URL with token and userId (userId for redundancy)
    private func buildSubscriptionURL(token: String, userId: String) -> URL? {
        guard var components = URLComponents(string: subscriptionBaseURL) else {
            return nil
        }
        
        // Include token AND userId for redundancy (webhook fallback)
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "returnUrl", value: "spotapp://subscription/return")
        ]
        
        return components.url
    }
    
    /// Builds subscription management URL with token and userId (userId for redundancy)
    private func buildManagementURL(token: String, userId: String) -> URL? {
        guard var components = URLComponents(string: subscriptionManageURL) else {
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "userId", value: userId),
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
