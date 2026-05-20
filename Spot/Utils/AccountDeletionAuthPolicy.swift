//
//  AccountDeletionAuthPolicy.swift
//  Spot
//
//  Chooses how account deletion re-authenticates the user. Apple-only accounts
//  must not be forced to set a password first (App Store Guideline 5.1.1(v)).
//

import Auth
import Foundation
import Supabase

enum AccountDeletionReauthMethod: Equatable {
    case password
    case signInWithApple
}

enum AccountDeletionAuthPolicy {
    /// Apple Sign In–only users re-auth with Apple; everyone else uses password.
    static func preferredReauthMethod(session: Session) -> AccountDeletionReauthMethod {
        let providers = linkedProviders(from: session)
        let hasApple = providers.contains("apple")
        let hasEmail = providers.contains("email")
        if hasApple, !hasEmail {
            return .signInWithApple
        }
        return .password
    }

    static func linkedProviders(from session: Session) -> Set<String> {
        linkedProviders(user: session.user)
    }

    static func linkedProviders(user: Auth.User) -> Set<String> {
        var providers = Set<String>()
        if let identities = user.identities {
            for identity in identities {
                providers.insert(identity.provider.lowercased())
            }
        }
        if let raw = user.appMetadata["provider"]?.stringValue?.lowercased(), !raw.isEmpty {
            providers.insert(raw)
        }
        return providers
    }
}
