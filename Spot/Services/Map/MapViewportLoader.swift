import Foundation
import MapKit
import FirebaseFirestore

/// Loads map spots for a viewport.
///
/// - When `FeedFlags.useSupabaseMapRPC` is true (default), calls
///   `public.get_map_spots_v1` (PostGIS bounding-box query). Server applies the
///   same privacy/blocking rules as the home feed; client signs primary
///   images only.
/// - Legacy path: Firestore geohash tile fetch with a tile cache. Kept behind
///   the flag for emergency rollback.
actor MapViewportLoader {
    static let shared = MapViewportLoader()

    /// Cache for the legacy geohash path. Keyed by geohash prefix.
    private var tileCache: [String: [Spot]] = [:]
    private let maxCachedTiles = 128

    /// Cache for the v2 PostGIS path. Keyed by quantized viewport (so adjacent
    /// pans don't refetch identical bounding boxes). Bounded LRU to keep memory
    /// in check on long sessions.
    private var viewportCache: [String: ([Spot], Date)] = [:]
    private var viewportLRU: [String] = []
    private let maxCachedViewports = 32
    private let viewportCacheTTL: TimeInterval = 60

    func clearCache() {
        tileCache.removeAll()
        viewportCache.removeAll()
        viewportLRU.removeAll()
    }

    /// Fetches map spots for the given region. Returned `Spot`s carry only a
    /// primary image URL — full image arrays are lazily loaded on detail.
    func load(region: MKCoordinateRegion, perTileLimit: Int = 200) async -> [Spot] {
        if FeedFlags.useSupabaseMapRPC {
            return await loadFromRPC(region: region, limit: perTileLimit)
        }
        return await loadFromGeohashTiles(region: region, perTileLimit: perTileLimit)
    }

    // MARK: - V2 (Supabase PostGIS)

    private func loadFromRPC(region: MKCoordinateRegion, limit: Int) async -> [Spot] {
        let bbox = boundingBox(for: region)
        let cacheKey = quantizedViewportKey(bbox)
        if let cached = viewportCache[cacheKey],
           Date().timeIntervalSince(cached.1) < viewportCacheTTL {
            return cached.0
        }

        do {
            let rows = try await FeedAPI.fetchMapSpots(
                minLat: bbox.minLat,
                minLng: bbox.minLng,
                maxLat: bbox.maxLat,
                maxLng: bbox.maxLng,
                centerLat: region.center.latitude,
                centerLng: region.center.longitude,
                limit: limit
            )

            let urlMap = await FeedAPI.resolvePrimaryImageURLs(for: rows)
            let hydrated = rows.map { $0.toSpot(primaryURL: urlMap[$0.spotId]) }

            viewportCache[cacheKey] = (hydrated, Date())
            viewportLRU.removeAll { $0 == cacheKey }
            viewportLRU.append(cacheKey)
            evictViewportIfNeeded()
            return hydrated
        } catch is CancellationError {
            // Pan/zoom-driven cancel — already logged at the FeedAPI layer
            // as `mapRPCCancelled` (debug). Don't double-log as failed.
            return []
        } catch {
            // The FeedAPI layer already classifies cancellations and logs
            // them as `mapRPCCancelled`. Anything reaching here that is
            // still a cancellation is also benign; surface only true
            // failures.
            let nsError = error as NSError
            let isCancellation =
                (nsError.code == NSURLErrorCancelled) ||
                ((error as? URLError)?.code == .cancelled) ||
                error.localizedDescription.lowercased().contains("cancelled")
            if isCancellation {
                return []
            }
            SpotLogger.log(FeedSupabaseLogs.mapRPCFailed, details: ["error": error.localizedDescription])
            return []
        }
    }

    private struct BoundingBox {
        let minLat: Double
        let minLng: Double
        let maxLat: Double
        let maxLng: Double
    }

    private func boundingBox(for region: MKCoordinateRegion) -> BoundingBox {
        let halfLat = max(region.span.latitudeDelta / 2.0, 0.001)
        let halfLng = max(region.span.longitudeDelta / 2.0, 0.001)
        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLng = region.center.longitude - halfLng
        let maxLng = region.center.longitude + halfLng
        return BoundingBox(
            minLat: max(-90, minLat),
            minLng: max(-180, minLng),
            maxLat: min(90, maxLat),
            maxLng: min(180, maxLng)
        )
    }

    /// Round bbox edges to a coarse grid so adjacent pans hit the same cache
    /// entry. Grid size scales with the viewport span: zoomed-in → finer grid,
    /// zoomed-out → coarser grid.
    private func quantizedViewportKey(_ bbox: BoundingBox) -> String {
        let span = max(bbox.maxLat - bbox.minLat, bbox.maxLng - bbox.minLng)
        let step: Double
        if span > 5 { step = 1.0 }
        else if span > 1 { step = 0.25 }
        else if span > 0.25 { step = 0.05 }
        else if span > 0.06 { step = 0.01 }
        else { step = 0.0025 }

        func q(_ x: Double) -> Double {
            (x / step).rounded() * step
        }
        return "\(q(bbox.minLat)),\(q(bbox.minLng)),\(q(bbox.maxLat)),\(q(bbox.maxLng))"
    }

    private func evictViewportIfNeeded() {
        while viewportLRU.count > maxCachedViewports {
            let key = viewportLRU.removeFirst()
            viewportCache.removeValue(forKey: key)
        }
    }

    // MARK: - Legacy (Firestore geohash)

    private func loadFromGeohashTiles(region: MKCoordinateRegion, perTileLimit: Int) async -> [Spot] {
        let prefixes = prefixesForRegion(region)
        let db = Firestore.firestore()

        var results: [Spot] = []
        var missing: [String] = []
        for p in prefixes {
            if let cached = tileCache[p] { results.append(contentsOf: cached) } else { missing.append(p) }
        }

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

        let filtered = await AuthorPrivacyCache.shared.filter(spots: results)
        return filtered
    }

    private func evictIfNeeded() {
        if tileCache.count <= maxCachedTiles { return }
        let dropCount = tileCache.count - maxCachedTiles
        for key in tileCache.keys.prefix(dropCount) { tileCache.removeValue(forKey: key) }
    }

    private func prefixesForRegion(_ region: MKCoordinateRegion) -> [String] {
        let latDelta = region.span.latitudeDelta
        let precision: Int
        if latDelta > 5 { precision = 4 } else if latDelta > 1 { precision = 5 } else if latDelta > 0.25 { precision = 6 } else if latDelta > 0.06 { precision = 7 } else { precision = 8 }

        let center = GeoHash.encode(latitude: region.center.latitude, longitude: region.center.longitude, precision: precision)
        var set: Set<String> = [center]
        for n in GeoHash.neighbors(of: center) { set.insert(n) }
        return Array(set)
    }
}
