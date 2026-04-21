//
//  SpotService.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation

final class SpotService {
    static let shared = SpotService()
    private init() {}
    private let mapSpotLimit = 250

    private var cachedSpots: [Spot] = []
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    private var isCacheValid: Bool {
        guard let lastFetch = lastFetchTime else { return false }
        return Date().timeIntervalSince(lastFetch) < cacheValidityDuration
    }

    func createSpot(imageURL: String, latitude: Double, longitude: Double, vibeTag: String, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(NSError(domain: "SpotService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Deprecated: use SpotPublishCoordinator/Supabase publish flow."])))
    }

    func fetchSpotsForMap(forceRefresh: Bool = false, completion: @escaping (Result<[Spot], Error>) -> Void) {
        // Return cached spots if available and cache is still valid
        if !forceRefresh && !cachedSpots.isEmpty && isCacheValid {
            SpotLogger.log(SpotServiceLogs.cachedSpotsReturned, details: ["count": cachedSpots.count])
            completion(.success(cachedSpots))
            return
        }

        SpotLogger.log(SpotServiceLogs.fetchSpotsStarted, details: ["orderBy": "created_at", "desc": true])
        Task {
            do {
                let spots = try await SpotSupabaseRepository.fetchMapSpots(limit: mapSpotLimit)
                let filtered = await AuthorPrivacyCache.shared.filter(spots: spots)
                self.cachedSpots = filtered
                self.lastFetchTime = Date()
                SpotLogger.log(SpotServiceLogs.spotsCachedForMap, details: ["count": filtered.count])
                completion(.success(filtered))
            } catch {
                SpotLogger.log(SpotServiceLogs.fetchSpotsError, details: ["error": error.localizedDescription])
                completion(.failure(error))
            }
        }
    }

    // MARK: - Fetch Single Spot

    func fetchSpotById(_ spotId: String, completion: @escaping (Result<Spot?, Error>) -> Void) {
        SpotLogger.log(SpotServiceLogs.fetchSpotByIdStarted, details: ["spotId": spotId])
        guard let sid = UUID(uuidString: spotId) else {
            completion(.success(nil))
            return
        }
        Task {
            do {
                let spots = try await SpotSupabaseRepository.fetchSpotsByIds([sid])
                guard var spot = spots.first else {
                    SpotLogger.log(SpotServiceLogs.spotNotFound, details: ["spotId": spotId])
                    completion(.success(nil))
                    return
                }
                if let owner = spot.userId {
                    let isBlocked = await self.checkIfUserIsBlocked(owner)
                    if isBlocked {
                        SpotLogger.log(SpotServiceLogs.spotOwnerBlocked, details: ["spotId": spotId])
                        completion(.success(nil))
                        return
                    }
                }
                if spot.id == nil { spot.id = spotId }
                SpotLogger.log(SpotServiceLogs.spotFetched, details: ["spotId": spotId])
                completion(.success(spot))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Async/await wrapper for existing callback API.
    func fetchSpotById(_ spotId: String) async throws -> Spot? {
        try await withCheckedThrowingContinuation { continuation in
            fetchSpotById(spotId) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func checkIfUserIsBlocked(_ userId: String) async -> Bool {
        guard let currentUserId = SpotAuthBridge.currentUserId else {
            return false
        }
        guard let blocker = UUID(uuidString: currentUserId), let blocked = UUID(uuidString: userId) else { return false }
        do {
            let rows: [IdOnly] = try await supabase
                .from("user_blocks")
                .select("id")
                .eq("blocker_id", value: blocker)
                .eq("blocked_user_id", value: blocked)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            SpotLogger.log(SpotServiceLogs.blockedUsersCheckFailed, details: ["error": error.localizedDescription])
            return false
        }
    }

    // MARK: - Delete Spot
    func deleteSpot(_ spot: Spot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = spot.id else {
            completion(.failure(NSError(domain: "SpotService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing spot id; cannot delete"])))
            return
        }
        guard let sid = UUID(uuidString: id) else {
            completion(.failure(NSError(domain: "SpotService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid spot id"])))
            return
        }
        Task {
            do {
                try await SpotSupabaseRepository.deleteSpot(id: sid)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Async/await wrapper for existing callback API.
    func deleteSpot(_ spot: Spot) async throws {
        try await withCheckedThrowingContinuation { continuation in
            deleteSpot(spot) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct IdOnly: Decodable { let id: UUID }
}
