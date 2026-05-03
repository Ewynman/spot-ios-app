import Foundation
import Supabase

struct SearchPage<T> {
    let items: [T]
    let lastDocument: String?
}

final class SpotSearchDataSource {
    private let pageSize = 24
    private let placesPage = 20

    private struct UserRow: Decodable {
        let id: UUID
        let username: String
        let profile_image_url: String?
    }

    // MARK: Users
    func searchUsers(prefix: String, last: String? = nil) async throws -> SearchPage<[String: Any]> {
        guard !prefix.isEmpty else { return SearchPage(items: [], lastDocument: nil) }
        let lower = prefix.lowercased()
        let rows: [UserRow] = try await supabase
            .from(SupabaseTableName.usersPublic)
            .select("id,username,profile_image_url")
            .limit(400)
            .execute()
            .value
        let filtered = rows.filter { $0.username.lowercased().hasPrefix(lower) }
            .prefix(pageSize)
        let items = filtered.map { row in
            [
                "uid": row.id.uuidString,
                "username": row.username,
                "profileImageURL": row.profile_image_url as Any
            ]
        }
        return SearchPage(items: items, lastDocument: nil)
    }

    // MARK: Locations (suggestions)
    func searchLocationSuggestions(prefix: String, limit: Int = 20) async throws -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        struct PlaceRow: Decodable { let name: String?; let location_name: String? }
        let rows: [PlaceRow] = try await supabase
            .from("spots")
            .select("location_name")
            .limit(300)
            .execute()
            .value
        let names = rows.compactMap { $0.location_name ?? $0.name }
        let titles = Array(Set(names.filter { $0.lowercased().hasPrefix(lower) })).sorted()
        SpotLogger.log(SearchDataSourceLogs.locationSuggestions, details: ["prefix": prefix, "count": titles.count])
        return Array(titles.prefix(limit))
    }

    // MARK: Vibes (suggestions)
    func searchVibeSuggestions(prefix: String, limit: Int = 20) async throws -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        struct Row: Decodable { let name: String }
        let rows: [Row] = try await supabase
            .from("vibe_tags")
            .select("name")
            .limit(300)
            .execute()
            .value
        let titles = Array(Set(rows.map(\.name).filter { $0.lowercased().hasPrefix(lower) })).sorted()
        SpotLogger.log(SearchDataSourceLogs.vibeSuggestions, details: ["prefix": prefix, "count": titles.count])
        return Array(titles.prefix(limit))
    }

    // MARK: Spots by exact location/vibe
    func fetchSpotsByLocation(_ locationLower: String, last: String? = nil) async throws -> SearchPage<Spot> {
        let spots = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: 500, offset: 0)
        let items = spots.filter { ($0.locationName ?? "").lowercased() == locationLower }
        return SearchPage(items: Array(items.prefix(pageSize)), lastDocument: nil)
    }

    func fetchSpotsByVibe(_ vibeLower: String, last: String? = nil) async throws -> SearchPage<Spot> {
        let spots = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: 500, offset: 0)
        let items = spots.filter { ($0.vibeTag ?? "").lowercased() == vibeLower }
        return SearchPage(items: Array(items.prefix(pageSize)), lastDocument: nil)
    }

    // MARK: Multiple vibes (Pro)
    func fetchSpotsByVibes(_ vibeLowers: [String], last: String? = nil) async throws -> SearchPage<Spot> {
        let lowers = Array(Set(vibeLowers.map { $0.lowercased() }))
        guard !lowers.isEmpty else { return SearchPage(items: [], lastDocument: nil) }
        let spots = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: 500, offset: 0)
        let items = spots.filter { lowers.contains(($0.vibeTag ?? "").lowercased()) }
        return SearchPage(items: Array(items.prefix(pageSize)), lastDocument: nil)
    }

    // MARK: Location + Multiple vibes (Pro)
    func fetchSpotsByLocationAndVibes(_ locationLower: String, vibeLowers: [String], last: String? = nil) async throws -> SearchPage<Spot> {
        let lowers = Array(Set(vibeLowers.map { $0.lowercased() }))
        guard !lowers.isEmpty else { return SearchPage(items: [], lastDocument: nil) }
        let spots = try await SpotSupabaseRepository.fetchGlobalFeedSpots(limit: 500, offset: 0)
        let filtered = spots.filter { spot in
            let locationMatch = (spot.locationName ?? "").lowercased() == locationLower
            let vibeMatch = lowers.contains((spot.vibeTag ?? "").lowercased())
            return locationMatch && vibeMatch
        }
        return SearchPage(items: Array(filtered.prefix(pageSize)), lastDocument: nil)
    }
}
