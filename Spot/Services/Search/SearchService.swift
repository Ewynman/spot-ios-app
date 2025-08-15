import Foundation
import FirebaseFirestore

final class SearchService {
    static let shared = SearchService()
    private init() {}

    private let fs = FirestoreSearchDataSource()
    private let privacy = AuthorPrivacyCache.shared

    func searchUsers(prefix: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<[String: Any]> {
        try await fs.searchUsers(prefix: prefix, last: last)
    }

    func searchLocationSuggestions(prefix: String) async throws -> [String] {
        try await fs.searchLocationSuggestions(prefix: prefix)
    }

    func searchVibeSuggestions(prefix: String) async throws -> [String] {
        try await fs.searchVibeSuggestions(prefix: prefix)
    }

    func fetchSpotsByLocation(_ locationLower: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        let page = try await fs.fetchSpotsByLocation(locationLower, last: last)
        let filtered = await privacy.filter(spots: page.items)
        return SearchPage(items: filtered, lastDocument: page.lastDocument)
    }

    func fetchSpotsByVibe(_ vibeLower: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        let page = try await fs.fetchSpotsByVibe(vibeLower, last: last)
        let filtered = await privacy.filter(spots: page.items)
        return SearchPage(items: filtered, lastDocument: page.lastDocument)
    }
}


