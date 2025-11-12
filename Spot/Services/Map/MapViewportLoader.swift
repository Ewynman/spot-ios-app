import Foundation
import MapKit
import FirebaseFirestore

actor MapViewportLoader {
    static let shared = MapViewportLoader()

    // Simple in-memory cache keyed by geohash prefix (actor-isolated)
    private var tileCache: [String: [Spot]] = [:]
    private let maxCachedTiles = 128

    func load(region: MKCoordinateRegion, perTileLimit: Int = 200) async -> [Spot] {
        let prefixes = prefixesForRegion(region)
        let db = Firestore.firestore()

        // Gather cached tiles immediately
        var results: [Spot] = []
        var missing: [String] = []
        for p in prefixes {
            if let cached = tileCache[p] { results.append(contentsOf: cached) } else { missing.append(p) }
        }

        // Parallel fetch missing tiles
        await withTaskGroup(of: (String, [Spot]).self) { group in
            for p in missing {
                group.addTask {
                    let start = p
                    let end = GeoHash.endRange(for: p)
                    do {
                        let snap = try await db.collection("spots")
                            .order(by: "geohash")
                            .whereField("geohash", isGreaterThanOrEqualTo: start)
                            .whereField("geohash", isLessThan: end)
                            .limit(to: perTileLimit)
                            .getDocuments()
                        var spots: [Spot] = []
                        for doc in snap.documents {
                            if var s = try? doc.data(as: Spot.self) {
                                s.id = doc.documentID
                                spots.append(s)
                            }
                        }
                        return (p, spots)
                    } catch {
                        return (p, [])
                    }
                }
            }
            for await (prefix, list) in group {
                results.append(contentsOf: list)
                tileCache[prefix] = list
                evictIfNeeded()
            }
        }

        // Apply privacy drop (call out of actor isolation not required; returns value)
        let filtered = await AuthorPrivacyCache.shared.filter(spots: results)
        return filtered
    }

    private func evictIfNeeded() {
        if tileCache.count <= maxCachedTiles { return }
        // naive eviction: drop first N keys
        let dropCount = tileCache.count - maxCachedTiles
        for key in tileCache.keys.prefix(dropCount) { tileCache.removeValue(forKey: key) }
    }

    private func prefixesForRegion(_ region: MKCoordinateRegion) -> [String] {
        let latDelta = region.span.latitudeDelta
        // Choose precision based on zoom: smaller span -> higher precision
        let precision: Int
        if latDelta > 5 { precision = 4 } else if latDelta > 1 { precision = 5 } else if latDelta > 0.25 { precision = 6 } else if latDelta > 0.06 { precision = 7 } else { precision = 8 }

        let center = GeoHash.encode(latitude: region.center.latitude, longitude: region.center.longitude, precision: precision)
        var set: Set<String> = [center]
        for n in GeoHash.neighbors(of: center) { set.insert(n) }
        return Array(set)
    }
}

