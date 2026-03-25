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

        SpotService.shared.fetchSpotsForMap(forceRefresh: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingAllSpots = false
                switch result {
                case .success(let spots):
                    self.visibleSpots = spots
                    SpotLogger.info("Map loaded all spots", details: ["count": spots.count])
                case .failure(let error):
                    SpotLogger.error("Failed to load all spots for map", details: ["error": error.localizedDescription])
                }
            }
        }
    }
}
