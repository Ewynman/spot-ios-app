//
//  SupabaseTableName.swift
//  Spot
//
//  Centralizes PostgREST table/view names used with the Supabase Swift client.
//

import Foundation

/// Public schema relation names for Supabase `.from(...)`.
enum SupabaseTableName {
    /// Full `public.users` row (RLS: own user id only). Includes `email` and server fields.
    static let users = "users"
    /// Safe profile projection for discovery and other users (no `email`). See `users_public` view.
    static let usersPublic = "users_public"
}
