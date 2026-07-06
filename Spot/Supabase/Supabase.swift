//
//  Supabase.swift
//  Spot
//
//  Created By Edward Wynman on 4/19/2026.
//

import Foundation
import Supabase

let supabase: SupabaseClient = {
    let config = SupabaseConfiguration.load()
    
    #if DEBUG
    // Log environment in DEBUG builds only (never log in production)
    print("🔧 Supabase Environment: \(config.environment.displayName)")
    print("🔧 Supabase URL: \(config.url.absoluteString)")
    #endif
    
    return SupabaseClient(
        supabaseURL: config.url,
        supabaseKey: config.anonKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}()
