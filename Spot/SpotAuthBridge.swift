import Foundation

/// Holds the active Supabase user id for call sites that are not yet async/session-aware.
enum SpotAuthBridge {
    nonisolated(unsafe) static var currentUserId: String?
    nonisolated(unsafe) static var currentUserEmail: String?
    nonisolated(unsafe) static var isEmailVerifiedForSession: Bool = false

    static func setSessionUser(id: String?, email: String?, emailVerified: Bool = false) {
        currentUserId = id
        currentUserEmail = email
        isEmailVerifiedForSession = emailVerified
    }
}
