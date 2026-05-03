//
//  SpotSupabaseRepository.swift
//  Spot
//
//  Reads / deletes spots stored in Postgres (public.spots + spot_images + vibe_tags).
//

import Foundation
import Supabase

enum SpotSupabaseRepository {
    /// Private bucket: `spot_images.storage_path` is the object key in the `spots` bucket (e.g. `userId/spotId_0.jpg`).
    /// `public_url` (if present) may hold the same path or a legacy full `https://` URL; signing uses `storage_path` first.
    private static let spotsStorageBucketId = "spots"
    private static let pendingImagesBucketId = "pending_images"

    private enum SupabasePlist {
        static let baseURL: URL = {
            guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
                  let root = NSDictionary(contentsOfFile: path) as? [String: Any],
                  let supabase = root["Supabase"] as? [String: Any],
                  let urlString = supabase["url"] as? String,
                  let url = URL(string: urlString)
            else {
                fatalError("Supabase.url missing in Info.plist")
            }
            return url
        }()

        static let anonKey: String = {
            guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
                  let root = NSDictionary(contentsOfFile: path) as? [String: Any],
                  let supabase = root["Supabase"] as? [String: Any],
                  let key = supabase["anonKey"] as? String,
                  !key.isEmpty
            else {
                fatalError("Supabase.anonKey missing in Info.plist")
            }
            return key
        }()
    }
    /// Signed URL lifetime for spot images (feed / grids refresh on reload).
    private static let spotImageSignedURLExpirySeconds = 604_800 // 7 days

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseTimestamptz(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = iso8601Fractional.date(from: raw) { return d }
        return iso8601Plain.date(from: raw)
    }

    private struct SpotRow: Decodable {
        let id: UUID
        let user_id: UUID
        let vibe_tag_id: UUID?
        let caption: String?
        let latitude: Double
        let longitude: Double
        let location_name: String?
        let likes_count: Int64?
        let author_is_private_snapshot: Bool?
        let created_at: String
        let media_display_aspect_ratio: Double?
        let media_count: Int64?
    }

    private struct SpotImageRow: Decodable {
        let spot_id: UUID
        let sort_index: Int
        let storage_path: String?
        let public_url: String?
        let storage_bucket: String?

        /// Object path inside the `spots` bucket, or a legacy absolute URL in `public_url`.
        var imageReference: String {
            let fromStorage = storage_path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromStorage.isEmpty { return fromStorage }
            return public_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private static func isStoredAbsoluteURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    /// Maps stored object paths to HTTPS URLs (signed per `storage_bucket`, default `spots`).
    static func resolveStoredImageURLs(paths: [String], buckets: [String?]) async throws -> [String] {
        guard !paths.isEmpty else { return [] }
        precondition(paths.count == buckets.count)

        struct BucketPath: Hashable {
            let bucket: String
            let path: String
        }

        var toSign = Set<BucketPath>()
        for (p, b) in zip(paths, buckets) where !isStoredAbsoluteURL(p) && !p.isEmpty {
            let bucket = b ?? spotsStorageBucketId
            toSign.insert(BucketPath(bucket: bucket, path: p))
        }

        var signedByKey: [BucketPath: String] = [:]
        let grouped = Dictionary(grouping: toSign, by: \.bucket)
        for (bucket, keys) in grouped {
            let uniquePaths = Array(Set(keys.map(\.path)))
            var offset = 0
            let chunkSize = 100
            while offset < uniquePaths.count {
                let end = min(offset + chunkSize, uniquePaths.count)
                let chunk = Array(uniquePaths[offset..<end])
                let signedResults = try await supabase.storage
                    .from(bucket)
                    .createSignedURLs(paths: chunk, expiresIn: spotImageSignedURLExpirySeconds)
                for item in signedResults {
                    if case let .success(path, url) = item {
                        signedByKey[BucketPath(bucket: bucket, path: path)] = url.absoluteString
                    }
                }
                offset = end
            }
        }

        return zip(paths, buckets).map { path, bucket in
            if isStoredAbsoluteURL(path) { return path }
            if path.isEmpty { return path }
            let b = bucket ?? spotsStorageBucketId
            return signedByKey[BucketPath(bucket: b, path: path)] ?? path
        }
    }

    private struct VibeRow: Decodable {
        let id: UUID
        let name: String
    }

    /// Spots for a profile grid, newest first.
    static func fetchSpotsForUser(
        userId: UUID,
        authorUsername: String,
        authorProfileImageURL: String?
    ) async throws -> [Spot] {
        let rows: [SpotRow] = try await supabase
            .from("spots")
            .select(spotRowSelectColumns)
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return try await mapRowsToSpots(
            rows,
            defaultUsername: authorUsername,
            defaultProfileURL: authorProfileImageURL
        )
    }

    /// Load spots by id (e.g. bookmark collection). Order matches input when possible.
    static func fetchSpotsByIds(_ ids: [UUID]) async throws -> [Spot] {
        guard !ids.isEmpty else { return [] }
        let rows: [SpotRow] = try await supabase
            .from("spots")
            .select(spotRowSelectColumns)
            .in("id", values: ids)
            .execute()
            .value

        let mapped = try await mapRowsToSpots(rows, defaultUsername: "User", defaultProfileURL: nil)
        let byId = Dictionary(uniqueKeysWithValues: mapped.compactMap { s -> (String, Spot)? in
            guard let id = s.id else { return nil }
            return (id, s)
        })
        return ids.compactMap { byId[$0.uuidString] }
    }

    /// First image URL per spot id (for collection cards). Order follows `spotIds`.
    static func fetchPreviewImageURLs(spotIds: [String]) async -> [String] {
        let uuids = spotIds.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [] }
        do {
            let images: [SpotImageRow] = try await supabase
                .from("spot_images")
                .select("spot_id,storage_path,public_url,sort_index,storage_bucket")
                .in("spot_id", values: uuids)
                .execute()
                .value
            var bestRow: [UUID: SpotImageRow] = [:]
            for img in images {
                if let cur = bestRow[img.spot_id] {
                    if img.sort_index < cur.sort_index { bestRow[img.spot_id] = img }
                } else {
                    bestRow[img.spot_id] = img
                }
            }
            var paths: [String] = []
            var buckets: [String?] = []
            for sid in spotIds {
                guard let u = UUID(uuidString: sid), let row = bestRow[u] else { continue }
                let ref = row.imageReference
                paths.append(ref)
                buckets.append(isStoredAbsoluteURL(ref) ? nil : (row.storage_bucket ?? spotsStorageBucketId))
            }
            return (try? await resolveStoredImageURLs(paths: paths, buckets: buckets)) ?? paths
        } catch {
            return []
        }
    }

    static func deleteSpot(id: UUID) async throws {
        try await supabase
            .from("spots")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func updateSpotMetadata(
        id: UUID,
        vibeTags: [String],
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws {
        guard let primaryVibe = vibeTags.first else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "At least one vibe is required"])
        }
        let vibeId = try await resolveOrCreateVibeTagId(displayName: primaryVibe)
        let trimmedPlace = locationName.trimmingCharacters(in: .whitespacesAndNewlines)

        struct SpotUpdate: Encodable {
            let vibe_tag_id: UUID
            let latitude: Double
            let longitude: Double
            let location_name: String
        }

        try await supabase
            .from("spots")
            .update(SpotUpdate(
                vibe_tag_id: vibeId,
                latitude: latitude,
                longitude: longitude,
                location_name: trimmedPlace
            ))
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Mapping

    private static func mapRowsToSpots(
        _ rows: [SpotRow],
        defaultUsername: String,
        defaultProfileURL: String?
    ) async throws -> [Spot] {
        guard !rows.isEmpty else { return [] }

        let vibeIds = Set(rows.compactMap(\.vibe_tag_id))
        var vibeNames: [UUID: String] = [:]
        if !vibeIds.isEmpty {
            let vibes: [VibeRow] = try await supabase
                .from("vibe_tags")
                .select("id,name")
                .in("id", values: Array(vibeIds))
                .execute()
                .value
            for v in vibes { vibeNames[v.id] = v.name }
        }

        let spotIds = rows.map(\.id)
        let images: [SpotImageRow] = try await supabase
            .from("spot_images")
            .select("spot_id,storage_path,public_url,sort_index,storage_bucket")
            .in("spot_id", values: spotIds)
            .execute()
            .value

        var imagesBySpot: [UUID: [SpotImageRow]] = [:]
        for img in images {
            imagesBySpot[img.spot_id, default: []].append(img)
        }
        for sid in imagesBySpot.keys {
            imagesBySpot[sid]?.sort { $0.sort_index < $1.sort_index }
        }

        let spotIdOrder = rows.map(\.id)
        var flatPaths: [String] = []
        var flatBuckets: [String?] = []
        for sid in spotIdOrder {
            for img in imagesBySpot[sid] ?? [] {
                let ref = img.imageReference
                flatPaths.append(ref)
                flatBuckets.append(isStoredAbsoluteURL(ref) ? nil : (img.storage_bucket ?? spotsStorageBucketId))
            }
        }
        let flatResolved = try await resolveStoredImageURLs(paths: flatPaths, buckets: flatBuckets)
        var cursor = 0
        var resolvedBySpot: [UUID: [String]] = [:]
        for sid in spotIdOrder {
            let n = (imagesBySpot[sid] ?? []).count
            resolvedBySpot[sid] = Array(flatResolved[cursor..<cursor + n])
            cursor += n
        }

        return rows.map { row in
            let urls = resolvedBySpot[row.id] ?? []
            let primary = urls.first
            let vibe = row.vibe_tag_id.flatMap { vibeNames[$0] } ?? ""
            let created = parseTimestamptz(row.created_at)
            return Spot(
                id: row.id.uuidString,
                userId: row.user_id.uuidString,
                username: defaultUsername,
                userProfileImageURL: defaultProfileURL,
                imageURL: primary,
                thumbnailURL: primary,
                vibeTag: vibe,
                latitude: row.latitude,
                longitude: row.longitude,
                locationName: row.location_name,
                likes: Int(row.likes_count ?? 0),
                isLiked: nil,
                isSaved: nil,
                createdAt: created,
                authorIsPrivate: row.author_is_private_snapshot,
                imageURLs: urls.isEmpty ? nil : urls,
                mediaDisplayAspectRatio: row.media_display_aspect_ratio,
                mediaCount: row.media_count.map { Int($0) }
            )
        }
    }

    private static let spotRowSelectColumns =
        "id,user_id,vibe_tag_id,caption,latitude,longitude,location_name,likes_count,author_is_private_snapshot,created_at,media_display_aspect_ratio,media_count,media_layout_version"

    private struct UserBriefRow: Decodable {
        let id: UUID
        let username: String
        let profile_image_url: String?
    }

    /// Map spot rows to `Spot` with per-author username / avatar from `public.users`.
    private static func mapRowsToSpotsPerAuthor(_ rows: [SpotRow]) async throws -> [Spot] {
        guard !rows.isEmpty else { return [] }

        let userIds = Array(Set(rows.map(\.user_id)))
        let users: [UserBriefRow] = try await supabase
            .from(SupabaseTableName.usersPublic)
            .select("id,username,profile_image_url")
            .in("id", values: userIds)
            .execute()
            .value
        var byUser: [UUID: UserBriefRow] = [:]
        for u in users { byUser[u.id] = u }

        let vibeIds = Set(rows.compactMap(\.vibe_tag_id))
        var vibeNames: [UUID: String] = [:]
        if !vibeIds.isEmpty {
            let vibes: [VibeRow] = try await supabase
                .from("vibe_tags")
                .select("id,name")
                .in("id", values: Array(vibeIds))
                .execute()
                .value
            for v in vibes { vibeNames[v.id] = v.name }
        }

        let spotIds = rows.map(\.id)
        let images: [SpotImageRow] = try await supabase
            .from("spot_images")
            .select("spot_id,storage_path,public_url,sort_index,storage_bucket")
            .in("spot_id", values: spotIds)
            .execute()
            .value

        var imagesBySpot: [UUID: [SpotImageRow]] = [:]
        for img in images {
            imagesBySpot[img.spot_id, default: []].append(img)
        }
        for sid in imagesBySpot.keys {
            imagesBySpot[sid]?.sort { $0.sort_index < $1.sort_index }
        }

        let spotIdOrder = rows.map(\.id)
        var flatPaths: [String] = []
        var flatBuckets: [String?] = []
        for sid in spotIdOrder {
            for img in imagesBySpot[sid] ?? [] {
                let ref = img.imageReference
                flatPaths.append(ref)
                flatBuckets.append(isStoredAbsoluteURL(ref) ? nil : (img.storage_bucket ?? spotsStorageBucketId))
            }
        }
        let flatResolved = try await resolveStoredImageURLs(paths: flatPaths, buckets: flatBuckets)
        var cursor = 0
        var resolvedBySpot: [UUID: [String]] = [:]
        for sid in spotIdOrder {
            let n = (imagesBySpot[sid] ?? []).count
            resolvedBySpot[sid] = Array(flatResolved[cursor..<cursor + n])
            cursor += n
        }

        return rows.map { row in
            let u = byUser[row.user_id]
            let urls = resolvedBySpot[row.id] ?? []
            let primary = urls.first
            let vibe = row.vibe_tag_id.flatMap { vibeNames[$0] } ?? ""
            let created = parseTimestamptz(row.created_at)
            return Spot(
                id: row.id.uuidString,
                userId: row.user_id.uuidString,
                username: u?.username ?? "User",
                userProfileImageURL: u?.profile_image_url,
                imageURL: primary,
                thumbnailURL: primary,
                vibeTag: vibe,
                latitude: row.latitude,
                longitude: row.longitude,
                locationName: row.location_name,
                likes: Int(row.likes_count ?? 0),
                isLiked: nil,
                isSaved: nil,
                createdAt: created,
                authorIsPrivate: row.author_is_private_snapshot,
                imageURLs: urls.isEmpty ? nil : urls,
                mediaDisplayAspectRatio: row.media_display_aspect_ratio,
                mediaCount: row.media_count.map { Int($0) }
            )
        }
    }

    // MARK: - Home feed candidates (offset pagination)

    static func fetchGlobalFeedSpots(limit: Int, offset: Int) async throws -> [Spot] {
        let rows: [SpotRow] = try await supabase
            .from("spots")
            .select(spotRowSelectColumns)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        return try await mapRowsToSpotsPerAuthor(rows)
    }

    /// Lightweight map dataset: one image per spot (for preview cards), bounded count.
    /// Avoids loading all image variants and keeps memory stable when opening the map.
    static func fetchMapSpots(limit: Int) async throws -> [Spot] {
        let rows: [SpotRow] = try await supabase
            .from("spots")
            .select(spotRowSelectColumns)
            .order("created_at", ascending: false)
            .range(from: 0, to: max(0, limit - 1))
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        let userIds = Array(Set(rows.map(\.user_id)))
        let users: [UserBriefRow] = try await supabase
            .from(SupabaseTableName.usersPublic)
            .select("id,username,profile_image_url")
            .in("id", values: userIds)
            .execute()
            .value
        var byUser: [UUID: UserBriefRow] = [:]
        for u in users { byUser[u.id] = u }

        let vibeIds = Set(rows.compactMap(\.vibe_tag_id))
        var vibeNames: [UUID: String] = [:]
        if !vibeIds.isEmpty {
            let vibes: [VibeRow] = try await supabase
                .from("vibe_tags")
                .select("id,name")
                .in("id", values: Array(vibeIds))
                .execute()
                .value
            for v in vibes { vibeNames[v.id] = v.name }
        }

        let orderedSpotIds = rows.map(\.id.uuidString)
        let previewURLs = await fetchPreviewImageURLs(spotIds: orderedSpotIds)
        var previewById: [String: String] = [:]
        for (sid, url) in zip(orderedSpotIds, previewURLs) {
            previewById[sid] = url
        }

        return rows.map { row in
            let sid = row.id.uuidString
            let u = byUser[row.user_id]
            let vibe = row.vibe_tag_id.flatMap { vibeNames[$0] } ?? ""
            let preview = previewById[sid]
            return Spot(
                id: sid,
                userId: row.user_id.uuidString,
                username: u?.username ?? "User",
                userProfileImageURL: u?.profile_image_url,
                imageURL: preview,
                thumbnailURL: preview,
                vibeTag: vibe,
                latitude: row.latitude,
                longitude: row.longitude,
                locationName: row.location_name,
                likes: Int(row.likes_count ?? 0),
                isLiked: nil,
                isSaved: nil,
                createdAt: parseTimestamptz(row.created_at),
                authorIsPrivate: row.author_is_private_snapshot,
                imageURLs: nil,
                mediaDisplayAspectRatio: row.media_display_aspect_ratio,
                mediaCount: row.media_count.map { Int($0) }
            )
        }
    }

    static func fetchFeedSpotsForAuthors(userIds: [UUID], limit: Int, offset: Int) async throws -> [Spot] {
        guard !userIds.isEmpty else { return [] }
        let rows: [SpotRow] = try await supabase
            .from("spots")
            .select(spotRowSelectColumns)
            .in("user_id", values: userIds)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        return try await mapRowsToSpotsPerAuthor(rows)
    }

    // MARK: - Publish (storage + inserts)

    private struct SpotIdRow: Decodable { let id: UUID }

    private struct UserPrivateRow: Decodable { let is_private: Bool }

    /// Resolve or create a row in `vibe_tags` and return its id.
    static func resolveOrCreateVibeTagId(displayName: String) async throws -> UUID {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Empty vibe name"])
        }
        let lower = name.lowercased()
        struct IdOnly: Decodable { let id: UUID }
        let existing: [IdOnly] = try await supabase
            .from("vibe_tags")
            .select("id")
            .eq("name_lower", value: lower)
            .limit(1)
            .execute()
            .value
        if let id = existing.first?.id { return id }

        struct VibeInsert: Encodable {
            let name: String
            let name_lower: String
        }
        do {
            let inserted: IdOnly = try await supabase
                .from("vibe_tags")
                .insert(VibeInsert(name: name, name_lower: lower))
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        } catch {
            let again: [IdOnly] = try await supabase
                .from("vibe_tags")
                .select("id")
                .eq("name_lower", value: lower)
                .limit(1)
                .execute()
                .value
            guard let id = again.first?.id else { throw error }
            return id
        }
    }

    private struct VibeTagPickerRow: Decodable {
        let id: UUID
        let name: String
        let name_lower: String?
    }

    /// Canonical rows from `vibe_tags` for search and post composer (ordered by `name_lower`).
    static func fetchVibeTagsForPicker(limit: Int = 1000) async throws -> [VibeTag] {
        let rows: [VibeTagPickerRow] = try await supabase
            .from("vibe_tags")
            .select("id,name,name_lower")
            .order("name_lower", ascending: true)
            .limit(limit)
            .execute()
            .value
        return rows.map { r in
            VibeTag(
                id: r.id.uuidString,
                name: r.name,
                name_lower: r.name_lower ?? r.name.lowercased(),
                createdAt: nil
            )
        }
    }

    /// Pending upload → Edge Function `moderate-image` → RPC `publish_spot_with_approved_media_assets_v1`.
    static func publishSpotFromDraft(
        userId: UUID,
        imageJPEGs: [Data],
        vibeTags: [String],
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> UUID {
        guard !imageJPEGs.isEmpty else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No images"])
        }

        guard let primaryVibe = vibeTags.first else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "At least one vibe is required"])
        }
        let vibeId = try await resolveOrCreateVibeTagId(displayName: primaryVibe)

        struct MediaAssetInsert: Encodable {
            let id: UUID
            let owner_id: UUID
            let kind: String
            let status: String
            let pending_bucket: String
            let pending_path: String
            let mime_type: String
            let byte_size: Int
            let width: Int?
            let height: Int?
        }

        struct PublishSpotRpcParams: Encodable {
            let p_vibe_tag_id: UUID
            let p_latitude: Double
            let p_longitude: Double
            let p_location_name: String
            let p_media_asset_ids: [UUID]
        }

        var approvedAssetIds: [UUID] = []
        for data in imageJPEGs {
            let assetId = UUID()
            let path = "\(userId.uuidString.lowercased())/\(assetId.uuidString.lowercased()).jpg"
            let pixelSize = SpotJPEGImageDimensions.pixelSize(jpeg: data)
            if let pixelSize {
                SpotLogger.log(SpotMediaLayoutLogs.jpegDimensionsRead, details: [
                    "assetId": assetId.uuidString,
                    "width": pixelSize.width,
                    "height": pixelSize.height,
                ])
                let displayRatio = SpotMediaAspectRatio.display(width: pixelSize.width, height: pixelSize.height)
                SpotLogger.log(SpotMediaLayoutLogs.displayRatioCalculated, details: [
                    "assetId": assetId.uuidString,
                    "displayRatio": String(describing: Double(displayRatio)),
                ])
            }
            try await supabase
                .from("media_assets")
                .insert(MediaAssetInsert(
                    id: assetId,
                    owner_id: userId,
                    kind: "spot_image",
                    status: "pending",
                    pending_bucket: pendingImagesBucketId,
                    pending_path: path,
                    mime_type: "image/jpeg",
                    byte_size: data.count,
                    width: pixelSize?.width,
                    height: pixelSize?.height
                ))
                .execute()
            if pixelSize != nil {
                SpotLogger.log(SpotMediaLayoutLogs.mediaAssetDimensionsAttached, details: ["assetId": assetId.uuidString])
            }

            try await supabase.storage
                .from(pendingImagesBucketId)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

            let moderate = try await invokeModerateImageFunction(mediaAssetId: assetId)
            guard moderate.approved else {
                if moderate.reason == "image_policy_rejected" {
                    throw NSError(
                        domain: "SpotImageModeration",
                        code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "One of your photos can't be posted. Please replace it and try again."]
                    )
                }
                    throw NSError(
                        domain: "SpotImageModeration",
                        code: 503,
                        userInfo: [NSLocalizedDescriptionKey: "We couldn't check one of your photos. Please try again."]
                    )
            }
            approvedAssetIds.append(assetId)
        }

        let trimmedPlace = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let spotIdString: String = try await supabase.rpc(
            "publish_spot_with_approved_media_assets_v1",
            params: PublishSpotRpcParams(
                p_vibe_tag_id: vibeId,
                p_latitude: latitude,
                p_longitude: longitude,
                p_location_name: trimmedPlace,
                p_media_asset_ids: approvedAssetIds
            )
        )
        .execute()
        .value

        guard let spotId = UUID(uuidString: spotIdString) else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid spot id from server"])
        }
        return spotId
    }

    /// Signed URL for the first image on a newly published spot (any approved storage bucket).
    static func signFirstImageURLForSpot(spotId: UUID) async throws -> String? {
        struct Row: Decodable {
            let storage_path: String?
            let storage_bucket: String?
            let sort_index: Int
        }
        let rows: [Row] = try await supabase
            .from("spot_images")
            .select("storage_path,storage_bucket,sort_index")
            .eq("spot_id", value: spotId)
            .order("sort_index", ascending: true)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        let ref = row.storage_path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ref.isEmpty { return nil }
        if isStoredAbsoluteURL(ref) { return ref }
        let bucket = row.storage_bucket ?? spotsStorageBucketId
        return try await supabase.storage
            .from(bucket)
            .createSignedURL(path: ref, expiresIn: spotImageSignedURLExpirySeconds)
            .absoluteString
    }

    /// Parses Edge Function JSON. **Contract:** body must include boolean `approved` (see `supabase/functions/moderate-image/index.ts`).
    /// A placeholder that returns only `{ "ok": true }` will parse as not approved and trigger the generic 503 user message.
    private static func parseModerateImageJSON(_ data: Data) -> (approved: Bool, reason: String?, jsonKeys: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, "moderation_unavailable", "")
        }
        let keys = obj.keys.sorted().joined(separator: ",")
        let approved = obj["approved"] as? Bool ?? false
        let reason =
            (obj["reason"] as? String)
            ?? (obj["error"] as? String)
        return (approved, reason, keys)
    }

    private static func invokeModerateImageFunction(mediaAssetId: UUID) async throws -> (approved: Bool, reason: String?) {
        let session = try await supabase.auth.session
        supabase.functions.setAuth(token: session.accessToken)
        let url = SupabasePlist.baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("moderate-image")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabasePlist.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["mediaAssetId": mediaAssetId.uuidString])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let parsed = parseModerateImageJSON(data)
        guard let http = resp as? HTTPURLResponse else {
            SpotLogger.log(SpotImageModerationLogs.moderateInvokeUnexpectedResponse, details: [
                "mediaAssetId": mediaAssetId.uuidString,
                "reason": "non_http_response",
            ])
            return (false, "moderation_unavailable")
        }

        let bodyPrefix = String(String(data: data, encoding: .utf8) ?? "").prefix(500)
        let outcome: (Bool, String?)
        if http.statusCode >= 500 {
            outcome = (false, parsed.reason ?? "moderation_unavailable")
        } else if http.statusCode == 422 {
            outcome = (parsed.approved, parsed.reason)
        } else if http.statusCode >= 400 {
            outcome = (false, parsed.reason ?? "moderation_unavailable")
        } else {
            outcome = (parsed.approved, parsed.reason)
        }

        if !outcome.0 {
            let isExpectedPolicy =
                http.statusCode == 422 && outcome.1 == "image_policy_rejected"
            if isExpectedPolicy {
                SpotLogger.log(SpotImageModerationLogs.policyRejectedByEdgeFunction, details: [
                    "mediaAssetId": mediaAssetId.uuidString,
                ])
            } else {
                SpotLogger.log(SpotImageModerationLogs.moderateInvokeUnexpectedResponse, details: [
                    "mediaAssetId": mediaAssetId.uuidString,
                    "httpStatus": String(http.statusCode),
                    "reason": outcome.1 ?? "",
                    "jsonKeys": parsed.jsonKeys,
                    "bodyPrefix": String(bodyPrefix),
                ])
            }
        }

        return outcome
    }
}
