import Foundation
import FirebaseFirestore

struct SearchPage<T> {
    let items: [T]
    let lastDocument: DocumentSnapshot?
}

final class FirestoreSearchDataSource {
    private let db = Firestore.firestore()
    private let pageSize = 24
    private let placesPage = 24

    // MARK: Users
    func searchUsers(prefix: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<[String: Any]> {
        guard !prefix.isEmpty else { throw NSError(domain: "FirestoreSearchDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Prefix is empty"]) }
        let lower = prefix.lowercased()
        do {
            // Try lowercased field prefix range first
            var query: Query = db.collection("users")
                .order(by: "username_lower")
                .start(at: [lower])
                .end(at: [lower + "\u{f8ff}"])
                .limit(to: pageSize)
            if let last { query = query.start(afterDocument: last) }
            let snap = try await query.getDocuments()
            var items = snap.documents.map { doc -> [String: Any] in
                var d = doc.data()
                d["uid"] = doc.documentID
                return d
            }
            if items.isEmpty {
                SpotLogger.debug("Search users: username_lower returned 0, falling back to username range")
                let cap = prefix
                var q: Query = db.collection("users")
                    .order(by: "username")
                    .start(at: [cap])
                    .end(at: [cap + "\u{f8ff}"])
                    .limit(to: pageSize)
                if let last { q = q.start(afterDocument: last) }
                let s2 = try await q.getDocuments()
                items = s2.documents.map { doc -> [String: Any] in
                    var d = doc.data()
                    d["uid"] = doc.documentID
                    return d
                }
                return SearchPage(items: items, lastDocument: s2.documents.last)
            }
            return SearchPage(items: items, lastDocument: snap.documents.last)
        } catch {
            // Fallback 1: case-sensitive range on original field with capitalized prefix
            let cap = prefix
            do {
                var q: Query = db.collection("users")
                    .order(by: "username")
                    .start(at: [cap])
                    .end(at: [cap + "\u{f8ff}"])
                    .limit(to: pageSize)
                if let last { q = q.start(afterDocument: last) }
                let snap = try await q.getDocuments()
                let items = snap.documents.map { doc -> [String: Any] in
                    var d = doc.data()
                    d["uid"] = doc.documentID
                    return d
                }
                return SearchPage(items: items, lastDocument: snap.documents.last)
            } catch {
                // Fallback 2: recent window filter (broad)
                let snap = try await db.collection("users").order(by: "createdAt", descending: true).limit(to: 500).getDocuments()
                let filtered = snap.documents.compactMap { doc -> [String: Any]? in
                    var d = doc.data()
                    let name = (d["username"] as? String)?.lowercased() ?? ""
                    guard name.hasPrefix(lower) else { return nil }
                    d["uid"] = doc.documentID
                    return d
                }
                return SearchPage(items: filtered, lastDocument: nil)
            }
        }
    }

    // MARK: Locations (suggestions)
    func searchLocationSuggestions(prefix: String, limit: Int = 20) async throws -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        do {
            // 0) First consult user-created canonical places
            var placeNames: [String] = []
            do {
                let ps = try await db.collection("places")
                    .order(by: "name_lower")
                    .start(at: [lower])
                    .end(at: [lower + "\u{f8ff}"])
                    .limit(to: limit)
                    .getDocuments()
                placeNames = ps.documents.compactMap { $0.data()["name"] as? String }
            } catch { }

            let snap = try await db.collection("spots")
                .order(by: "locationName_lower")
                .start(at: [lower])
                .end(at: [lower + "\u{f8ff}"])
                .limit(to: limit)
                .getDocuments()
            var set = Set<String>()
            for n in placeNames { set.insert(n.lowercased()) }
            for d in snap.documents {
                if let name = (d.data()["locationName_lower"] as? String) ?? (d.data()["locationName"] as? String)?.lowercased() {
                    set.insert(name)
                }
            }
            let titles = Array(set).sorted()
            SpotLogger.debug("Location suggestions (prefix=\(prefix)) -> \(titles.count)")
            return titles
        } catch {
            let snap = try await db.collection("spots").order(by: "createdAt", descending: true).limit(to: 200).getDocuments()
            var set = Set<String>()
            for d in snap.documents {
                let name = (d.data()["locationName"] as? String)?.lowercased() ?? ""
                if name.hasPrefix(lower) { set.insert(name) }
            }
            let titles = Array(set).sorted()
            SpotLogger.debug("Location suggestions Fallback (prefix=\(prefix)) -> \(titles.count)")
            return titles
        }
    }

    // MARK: Vibes (suggestions)
    func searchVibeSuggestions(prefix: String, limit: Int = 20) async throws -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        do {
            let snap = try await db.collection("spots")
                .order(by: "vibeTag_lower")
                .start(at: [lower])
                .end(at: [lower + "\u{f8ff}"])
                .limit(to: limit)
                .getDocuments()
            var set = Set<String>()
            for d in snap.documents {
                if let vibe = (d.data()["vibeTag_lower"] as? String) ?? (d.data()["vibeTag"] as? String)?.lowercased() {
                    set.insert(vibe)
                }
            }
            let titles = Array(set).sorted()
            SpotLogger.debug("Vibe suggestions (prefix=\(prefix)) -> \(titles.count)")
            return titles
        } catch {
            let snap = try await db.collection("spots").order(by: "createdAt", descending: true).limit(to: 200).getDocuments()
            var set = Set<String>()
            for d in snap.documents {
                let vibe = (d.data()["vibeTag"] as? String)?.lowercased() ?? ""
                if vibe.hasPrefix(lower) { set.insert(vibe) }
            }
            let titles = Array(set).sorted()
            SpotLogger.debug("Vibe suggestions Fallback (prefix=\(prefix)) -> \(titles.count)")
            return titles
        }
    }

    // MARK: Spots by exact location/vibe
    func fetchSpotsByLocation(_ locationLower: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        var query: Query = db.collection("spots")
            .whereField("locationName_lower", isEqualTo: locationLower)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        if let last { query = query.start(afterDocument: last) }
        do {
            let snap = try await query.getDocuments()
            var items = snap.documents.compactMap { try? $0.data(as: Spot.self) }
            if items.isEmpty {
                SpotLogger.debug("Grid fallback: no locationName_lower matches; trying range on locationName")
                // Fallback: range on original cased field and client-filter by exact lowercase
                var q2: Query = db.collection("spots")
                    .order(by: "locationName")
                    .start(at: [locationLower])
                    .end(at: [locationLower + "\u{f8ff}"])
                    .limit(to: 100)
                if let last { q2 = q2.start(afterDocument: last) }
                let s2 = try await q2.getDocuments()
                items = s2.documents.compactMap { doc in
                    let data = doc.data()
                    let name = (data["locationName"] as? String)?.lowercased()
                    if name == locationLower { return try? doc.data(as: Spot.self) }
                    return nil
                }
                return SearchPage(items: items, lastDocument: s2.documents.last)
            }
            return SearchPage(items: items, lastDocument: snap.documents.last)
        } catch {
            // Final fallback: scan recent docs and client-filter by exact lowercase equality
            let s3 = try await db.collection("spots")
                .order(by: "createdAt", descending: true)
                .limit(to: 500)
                .getDocuments()
            let items = s3.documents.compactMap { doc -> Spot? in
                let data = doc.data()
                let name = (data["locationName"] as? String)?.lowercased()
                guard name == locationLower else { return nil }
                return try? doc.data(as: Spot.self)
            }
            return SearchPage(items: Array(items.prefix(pageSize)), lastDocument: nil)
        }
    }

    func fetchSpotsByVibe(_ vibeLower: String, last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        var query: Query = db.collection("spots")
            .whereField("vibeTag_lower", isEqualTo: vibeLower)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)
        if let last { query = query.start(afterDocument: last) }
        do {
            let snap = try await query.getDocuments()
            var items = snap.documents.compactMap { try? $0.data(as: Spot.self) }
            if items.isEmpty {
                SpotLogger.debug("Grid fallback: no vibeTag_lower matches; trying range on vibeTag")
                var q2: Query = db.collection("spots")
                    .order(by: "vibeTag")
                    .start(at: [vibeLower])
                    .end(at: [vibeLower + "\u{f8ff}"])
                    .limit(to: 100)
                if let last { q2 = q2.start(afterDocument: last) }
                let s2 = try await q2.getDocuments()
                items = s2.documents.compactMap { doc in
                    let data = doc.data()
                    let tag = (data["vibeTag"] as? String)?.lowercased()
                    if tag == vibeLower { return try? doc.data(as: Spot.self) }
                    return nil
                }
                return SearchPage(items: items, lastDocument: s2.documents.last)
            }
            return SearchPage(items: items, lastDocument: snap.documents.last)
        } catch {
            let s3 = try await db.collection("spots")
                .order(by: "createdAt", descending: true)
                .limit(to: 500)
                .getDocuments()
            let items = s3.documents.compactMap { doc -> Spot? in
                let data = doc.data()
                let tag = (data["vibeTag"] as? String)?.lowercased()
                guard tag == vibeLower else { return nil }
                return try? doc.data(as: Spot.self)
            }
            return SearchPage(items: Array(items.prefix(pageSize)), lastDocument: nil)
        }
    }

    // MARK: Multiple vibes (Pro)
    func fetchSpotsByVibes(_ vibeLowers: [String], last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        let lowers = Array(Set(vibeLowers.map { $0.lowercased() }))
        guard !lowers.isEmpty else { return SearchPage(items: [], lastDocument: nil) }

        if lowers.count <= 10 {
            var query: Query = db.collection("spots")
                .whereField("vibeTag_lower", in: lowers)
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            if let last { query = query.start(afterDocument: last) }
            let snap = try await query.getDocuments()
            let items = snap.documents.compactMap { try? $0.data(as: Spot.self) }
            return SearchPage(items: items, lastDocument: snap.documents.last)
        }

        // Fallback: too many tags for Firestore 'in'. Merge recent pages per tag client-side.
        var merged: [Spot] = []
        var ids = Set<String>()
        for tag in lowers.prefix(20) { // cap to avoid too many queries
            let page = try await fetchSpotsByVibe(tag, last: nil)
            for s in page.items {
                let id = s.id ?? ""
                if !id.isEmpty && !ids.contains(id) {
                    ids.insert(id)
                    merged.append(s)
                }
            }
        }
        merged.sort { (a, b) in
            let ad = a.createdAt ?? .distantPast
            let bd = b.createdAt ?? .distantPast
            return ad > bd
        }
        return SearchPage(items: Array(merged.prefix(pageSize)), lastDocument: nil)
    }

    // MARK: Location + Multiple vibes (Pro)
    func fetchSpotsByLocationAndVibes(_ locationLower: String, vibeLowers: [String], last: DocumentSnapshot? = nil) async throws -> SearchPage<Spot> {
        let lowers = Array(Set(vibeLowers.map { $0.lowercased() }))
        guard !lowers.isEmpty else { return SearchPage(items: [], lastDocument: nil) }

        // Firestore limitation: can only use 'in' with one field, so we filter by location first, then client-filter by vibes
        // This is efficient if location filter is selective
        var query: Query = db.collection("spots")
            .whereField("locationName_lower", isEqualTo: locationLower)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize * 3) // Fetch more to account for client-side filtering
        if let last { query = query.start(afterDocument: last) }
        
        do {
            let snap = try await query.getDocuments()
            let allItems = snap.documents.compactMap { try? $0.data(as: Spot.self) }
            // Client-side filter by vibe tags
            let filtered = allItems.filter { spot in
                guard let tag = spot.vibeTag?.lowercased() else { return false }
                return lowers.contains(tag)
            }
            // Remove duplicates and limit
            var seen = Set<String>()
            var unique: [Spot] = []
            for spot in filtered {
                let id = spot.id ?? UUID().uuidString
                if !seen.contains(id) {
                    seen.insert(id)
                    unique.append(spot)
                    if unique.count >= pageSize { break }
                }
            }
            return SearchPage(items: unique, lastDocument: snap.documents.last)
        } catch {
            // Fallback: fetch by location, then client-filter
            let page = try await fetchSpotsByLocation(locationLower, last: last)
            let filtered = page.items.filter { spot in
                guard let tag = spot.vibeTag?.lowercased() else { return false }
                return lowers.contains(tag)
            }
            return SearchPage(items: filtered, lastDocument: page.lastDocument)
        }
    }
}

// Firestore composite indexes required:
// 1) spots: locationName_lower ASC, createdAt DESC
// 2) spots: vibeTag_lower ASC, createdAt DESC
// Single-field index: users.username_lower ASC
