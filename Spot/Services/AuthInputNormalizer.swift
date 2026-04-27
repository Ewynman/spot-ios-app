//
//  AuthInputNormalizer.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 04/27/2026
//
//  Pure helpers for the auth pipeline so input normalization and error
//  classification can be exercised in isolation. AuthService routes its
//  inline string handling through these helpers to keep behavior identical.
//

import Foundation

enum AuthInputNormalizer {
    /// Normalizes user-entered email by trimming surrounding whitespace and
    /// lowercasing. Supabase treats emails case-insensitively but persists the
    /// exact casing it receives, so callers should always normalize first.
    static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trims user-entered username without changing case. Username casing is
    /// preserved for display, while `username_lower` is computed separately
    /// for case-insensitive uniqueness checks.
    static func normalizeUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased copy of a normalized username for case-insensitive lookups.
    static func normalizeUsernameLower(_ raw: String) -> String {
        normalizeUsername(raw).lowercased()
    }
}

enum AuthErrorClassifier {
    /// Heuristic match for "email already exists" errors returned by Supabase
    /// auth. Supabase doesn't surface a stable error code, so we lowercase the
    /// localized description and look for any of the known phrases.
    static func isEmailInUse(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("already")
            || lower.contains("exists")
            || lower.contains("registered")
    }

    /// Convenience overload that pulls the localized description from an Error
    /// before classifying.
    static func isEmailInUse(error: Error) -> Bool {
        isEmailInUse(error.localizedDescription)
    }
}
