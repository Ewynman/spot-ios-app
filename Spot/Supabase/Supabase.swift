//
//  Supabase.swift
//  Spot
//
//  Created By Edward Wynman on 4/19/2026.
//

import Foundation
import Supabase

private enum SupabaseConfiguration {
    static func load() -> (url: URL, anonKey: String) {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let root = NSDictionary(contentsOfFile: path) as? [String: Any],
              let supabase = root["Supabase"] as? [String: Any],
              let urlString = supabase["url"] as? String,
              let anonKey = supabase["anonKey"] as? String,
              let url = URL(string: urlString),
              !anonKey.isEmpty
        else {
            fatalError("Add Supabase.url and Supabase.anonKey to Info.plist (see Supabase dashboard).")
        }
        return (url, anonKey)
    }
}

let supabase: SupabaseClient = {
    let (url, anonKey) = SupabaseConfiguration.load()
    return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
}()
