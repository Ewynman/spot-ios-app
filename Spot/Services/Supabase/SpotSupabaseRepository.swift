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
    }

    private struct SpotImageRow: Decodable {
        let spot_id: UUID
        let sort_index: Int
        let storage_path: String?
        let public_url: String?

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

    /// Maps stored object paths to HTTPS URLs (signed for storage paths).
    private static func resolveStoredImageURLs(_ stored: [String]) async throws -> [String] {
        guard !stored.isEmpty else { return [] }
        var uniquePaths: [String] = []
        var seen = Set<String>()
        for s in stored where !isStoredAbsoluteURL(s) && !s.isEmpty {
            if seen.insert(s).inserted {
                uniquePaths.append(s)
            }
        }
        var pathToSigned: [String: String] = [:]
        let chunkSize = 100
        var offset = 0
        while offset < uniquePaths.count {
            let end = min(offset + chunkSize, uniquePaths.count)
            let chunk = Array(uniquePaths[offset..<end])
            let signed = try await supabase.storage
                .from(spotsStorageBucketId)
                .createSignedURLs(paths: chunk, expiresIn: spotImageSignedURLExpirySeconds)
            for (path, url) in zip(chunk, signed) {
                pathToSigned[path] = url.absoluteString
            }
            offset = end
        }
        return stored.map { s in
            if isStoredAbsoluteURL(s) { return s }
            return pathToSigned[s] ?? s
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
            .select("id,user_id,vibe_tag_id,caption,latitude,longitude,location_name,likes_count,author_is_private_snapshot,created_at")
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
            .select("id,user_id,vibe_tag_id,caption,latitude,longitude,location_name,likes_count,author_is_private_snapshot,created_at")
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
                .select("spot_id,storage_path,public_url,sort_index")
                .in("spot_id", values: uuids)
                .execute()
                .value
            var best: [UUID: (url: String, sort: Int)] = [:]
            for img in images {
                let ref = img.imageReference
                if let cur = best[img.spot_id] {
                    if img.sort_index < cur.sort { best[img.spot_id] = (ref, img.sort_index) }
                } else {
                    best[img.spot_id] = (ref, img.sort_index)
                }
            }
            let ordered = spotIds.compactMap { sid -> String? in
                guard let u = UUID(uuidString: sid) else { return nil }
                return best[u]?.url
            }
            return (try? await resolveStoredImageURLs(ordered)) ?? ordered
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
            .select("spot_id,storage_path,public_url,sort_index")
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
        var flatStored: [String] = []
        for sid in spotIdOrder {
            flatStored.append(contentsOf: (imagesBySpot[sid] ?? []).map(\.imageReference))
        }
        let flatResolved = try await resolveStoredImageURLs(flatStored)
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
                imageURLs: urls.isEmpty ? nil : urls
            )
        }
    }

    private static let spotRowSelectColumns =
        "id,user_id,vibe_tag_id,caption,latitude,longitude,location_name,likes_count,author_is_private_snapshot,created_at"

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
            .from("users")
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
            .select("spot_id,storage_path,public_url,sort_index")
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
        var flatStored: [String] = []
        for sid in spotIdOrder {
            flatStored.append(contentsOf: (imagesBySpot[sid] ?? []).map(\.imageReference))
        }
        let flatResolved = try await resolveStoredImageURLs(flatStored)
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
                imageURLs: urls.isEmpty ? nil : urls
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
            .from("users")
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
                imageURLs: nil
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

    /// Uploads JPEGs to the `spots` storage bucket, inserts `spots` + `spot_images`. Returns new spot id.
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

        let privacyRow: UserPrivateRow = try await supabase
            .from("users")
            .select("is_private")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        guard let primaryVibe = vibeTags.first else {
            throw NSError(domain: "SpotSupabaseRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "At least one vibe is required"])
        }
        let vibeId = try await resolveOrCreateVibeTagId(displayName: primaryVibe)

        struct SpotInsert: Encodable {
            let user_id: UUID
            let vibe_tag_id: UUID
            let caption: String?
            let latitude: Double
            let longitude: Double
            let location_name: String
            let author_is_private_snapshot: Bool
        }

        let trimmedPlace = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let spotRow: SpotIdRow = try await supabase
            .from("spots")
            .insert(SpotInsert(
                user_id: userId,
                vibe_tag_id: vibeId,
                caption: nil,
                latitude: latitude,
                longitude: longitude,
                location_name: trimmedPlace,
                author_is_private_snapshot: privacyRow.is_private
            ))
            .select("id")
            .single()
            .execute()
            .value

        let spotId = spotRow.id

        struct SpotImageInsert: Encodable {
            let spot_id: UUID
            let storage_path: String
            let public_url: String
            let sort_index: Int
        }

        for (idx, data) in imageJPEGs.enumerated() {
            let path = "\(userId.uuidString.lowercased())/\(spotId.uuidString.lowercased())_\(idx).jpg"
            try await supabase.storage
                .from(spotsStorageBucketId)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            try await supabase
                .from("spot_images")
                .insert(SpotImageInsert(spot_id: spotId, storage_path: path, public_url: path, sort_index: idx))
                .execute()
        }

        return spotId
    }
}
