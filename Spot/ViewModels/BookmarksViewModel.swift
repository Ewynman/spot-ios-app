//
//  BookmarksViewModel.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class BookmarksViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var errorMessage: String?

    private var lastCursor: DocumentSnapshot?
    private var loadedSpotIds = Set<String>() // For deduplication within session
    private let pageSize = 24

    func loadInitial() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await UserSpotService.shared.fetchBookmarkedSpots(pageSize: pageSize)

            // Filter out duplicates within session
            let newSpots = result.spots.filter { spot in
                guard let spotId = spot.id else { return false }
                let isNew = !loadedSpotIds.contains(spotId)
                if isNew {
                    loadedSpotIds.insert(spotId)
                }
                return isNew
            }

            spots = newSpots
            lastCursor = result.lastCursor
            hasMore = result.hasMore

            SpotLogger.info("BookmarksViewModel: Loaded \(newSpots.count) spots, hasMore: \(hasMore)")
        } catch {
            errorMessage = "Failed to load bookmarked spots"
            SpotLogger.error("BookmarksViewModel loadInitial failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func loadMore() async {
        // No pagination for array-based approach
        // This method is kept for future subcollection implementation
        return
    }

    func refresh() async {
        // Reset state for fresh load
        spots = []
        loadedSpotIds.removeAll()
        lastCursor = nil
        hasMore = true

        await loadInitial()
    }

    func removeSpot(_ spot: Spot) {
        guard let spotId = spot.id else { return }
        spots.removeAll { $0.id == spotId }
        loadedSpotIds.remove(spotId)
    }
}
