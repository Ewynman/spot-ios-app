//
//  AuthProfileSetupGate.swift
//  Spot
//
//  Decides whether the post-auth “complete profile” flow should run for the
//  current session. Email/password signups already collect username + photo
//  in onboarding; Apple sign-in may not have both persisted yet.
//

import Auth
import Foundation
import Supabase

enum AuthProfileSetupGate {
    /// True when the user signed in with Apple (or has an Apple identity linked).
    static func shouldShowUsernamePhotoPostAuthSetup(session: Session) -> Bool {
        if let identities = session.user.identities {
            for identity in identities where identity.provider.lowercased() == "apple" {
                return true
            }
        }
        if let raw = session.user.appMetadata["provider"]?.stringValue?.lowercased(), raw == "apple" {
            return true
        }
        return false
    }
}
