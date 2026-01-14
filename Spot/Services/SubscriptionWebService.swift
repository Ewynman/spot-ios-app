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
    
    // Base URL for subscription website - update this with your actual website URL
    private let subscriptionBaseURL = "https://spotapp.online/subscribe" // TODO: Update with actual URL
    
    func openSubscriptionPage(userId: String, email: String?, username: String?) {
        guard let url = buildSubscriptionURL(userId: userId, email: email, username: username) else {
            SpotLogger.error("SubscriptionWebService: Failed to build subscription URL", details: ["userId": userId])
            return
        }
        
        SpotLogger.info("SubscriptionWebService: Opening subscription page", details: ["url": url.absoluteString, "userId": userId])
        
        // Open in Safari (external browser) so user can complete payment
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                SpotLogger.info("SubscriptionWebService: Successfully opened subscription page")
            } else {
                SpotLogger.error("SubscriptionWebService: Failed to open subscription page")
            }
        }
    }
    
    private func buildSubscriptionURL(userId: String, email: String?, username: String?) -> URL? {
        guard var components = URLComponents(string: subscriptionBaseURL) else {
            return nil
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "returnUrl", value: "spotapp://subscription/return")
        ]
        
        if let email = email {
            queryItems.append(URLQueryItem(name: "email", value: email))
        }
        
        if let username = username {
            queryItems.append(URLQueryItem(name: "username", value: username))
        }
        
        components.queryItems = queryItems
        
        return components.url
    }
    
    func openSubscriptionPageForCurrentUser() {
        guard let user = Auth.auth().currentUser else {
            SpotLogger.error("SubscriptionWebService: No current user", details: [:])
            return
        }
        
        // Fetch username from Firestore
        Task {
            do {
                let userDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(user.uid)
                    .getDocument()
                
                let username = userDoc.data()?["username"] as? String
                
                await MainActor.run {
                    openSubscriptionPage(
                        userId: user.uid,
                        email: user.email,
                        username: username
                    )
                }
            } catch {
                SpotLogger.error("SubscriptionWebService: Failed to fetch user data", details: ["error": error.localizedDescription])
                // Still open with just userId and email
                await MainActor.run {
                    openSubscriptionPage(
                        userId: user.uid,
                        email: user.email,
                        username: nil
                    )
                }
            }
        }
    }
}
