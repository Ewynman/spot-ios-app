//
//  FeedViewModel.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation

class FeedViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var mapSpots: [Spot] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var deletingSpotIds: Set<String> = []
    private var loadTask: Task<Void, Never>?
    private let repo = FeedRepository.shared
    private var hasRecordedFirstItem = false

    deinit {
        loadTask?.cancel()
    }

    /// Spots for feed list (no filtering).
    var validSpots: [Spot] { spots }

    /// Spots with valid coordinates for map display.
    var validMapSpots: [Spot] {
        mapSpots.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// Call when feed state is updated; records first-item metric once. No PerfMetrics in views.
    func recordFirstItemIfNeeded() {
        guard !hasRecordedFirstItem, !spots.isEmpty else { return }
        hasRecordedFirstItem = true
        let t = PerfMetrics.shared.measure("t_first_item") ?? 0
        PerfMetrics.shared.recordOnce("t_first_item", value: t)
    }

    func loadInitialSpots() async {
        loadTask?.cancel()
        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadInitial()
            await MainActor.run {
                self.spots = repo.spots
                self.hasMore = repo.moreAvailable
                self.isLoading = false
                recordFirstItemIfNeeded()
            }
        }
    }

    func loadMoreSpots() {
        guard !isLoading, hasMore else { return }

        loadTask?.cancel()

        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadMore()
            await MainActor.run {
                let new = repo.spots
                self.spots = new
                self.hasMore = repo.moreAvailable
                self.isLoading = false
                recordFirstItemIfNeeded()
            }
        }
    }

    func refreshFeed() async {
        loadTask?.cancel()

        loadTask = Task {
            await MainActor.run { self.isLoading = true }
            await repo.loadInitial()
            await MainActor.run {
                self.spots = repo.spots
                self.hasMore = repo.moreAvailable
                self.isLoading = false
                recordFirstItemIfNeeded()
            }
        }
        await loadTask?.value
    }

    // MARK: - Insert newly posted spot
    @MainActor
    func insertNewSpot(_ spot: Spot) {
        spots.removeAll { $0.id == spot.id }
        spots.insert(spot, at: 0)
        SpotLogger.log(FeedViewModelLogs.insertedNewSpotAtTop, details: ["spotId": spot.safeId])
    }

    func loadMapSpots(forceRefresh: Bool = false) {
        SpotLogger.log(FeedViewModelLogs.mapSpotsWarmDisabled)
        self.mapSpots = []
    }

    // MARK: - Delete
    @MainActor
    func delete(spot: Spot) async {
        guard let id = spot.id else {
            SpotLogger.log(FeedViewModelLogs.deleteRequestedWithoutId)
            return
        }
        guard let uuid = UUID(uuidString: id) else {
            SpotLogger.log(FeedViewModelLogs.deleteInvalidSpotId, details: ["spotId": id])
            return
        }
        if deletingSpotIds.contains(id) { return }
        deletingSpotIds.insert(id)

        let prevSpots = spots
        let prevMap = mapSpots
        spots.removeAll { $0.id == id }
        mapSpots.removeAll { $0.id == id }

        do {
            SpotLogger.log(FeedViewModelLogs.deletingSpot, details: ["spotId": id])
            try await SpotSupabaseRepository.deleteSpot(id: uuid)
            deletingSpotIds.remove(id)
            loadMapSpots(forceRefresh: true)
        } catch {
            SpotLogger.log(FeedViewModelLogs.deleteFailed, details: ["spotId": id, "error": error.localizedDescription])
            spots = prevSpots
            mapSpots = prevMap
            deletingSpotIds.remove(id)
        }
    }
}
