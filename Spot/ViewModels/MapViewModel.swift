//
//  MapViewModel.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation

@MainActor
final class MapViewModel: ObservableObject {
    @Published var visibleSpots: [Spot] = []
    @Published var isLoadingAllSpots: Bool = false

    func loadAllSpots() {
        guard !isLoadingAllSpots else { return }
        isLoadingAllSpots = true

        SpotService.shared.fetchSpotsForMap(forceRefresh: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingAllSpots = false
                switch result {
                case .success(let spots):
                    self.visibleSpots = spots
                    SpotLogger.log(MapViewModelLogs.mapLoadedAllSpots, details: ["count": spots.count])
                case .failure(let error):
                    SpotLogger.log(MapViewModelLogs.loadAllSpotsFailed, details: ["error": error.localizedDescription])
                }
            }
        }
    }

    func clearVisibleSpots() {
        visibleSpots.removeAll(keepingCapacity: false)
    }
}
