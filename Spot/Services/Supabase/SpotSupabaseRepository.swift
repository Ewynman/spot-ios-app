//
//  SpotSupabaseRepository.swift
//  Spot
//
//  Reads / deletes spots stored in Postgres (public.spots + spot_images + vibe_tags).
//

import Foundation
import Supabase

enum SpotSupabaseRepository {
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
        let public_url: String
        let sort_index: Int
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
                .select("spot_id,public_url,sort_index")
                .in("spot_id", values: uuids)
                .execute()
                .value
            var best: [UUID: (url: String, sort: Int)] = [:]
            for img in images {
                if let cur = best[img.spot_id] {
                    if img.sort_index < cur.sort { best[img.spot_id] = (img.public_url, img.sort_index) }
                } else {
                    best[img.spot_id] = (img.public_url, img.sort_index)
                }
            }
            return spotIds.compactMap { sid in
                guard let u = UUID(uuidString: sid) else { return nil }
                return best[u]?.url
            }
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
            .select("spot_id,public_url,sort_index")
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

        return rows.map { row in
            let ordered = imagesBySpot[row.id] ?? []
            let urls = ordered.map(\.public_url)
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
}
