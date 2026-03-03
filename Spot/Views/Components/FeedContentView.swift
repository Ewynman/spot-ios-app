//
//  FeedContentView.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import SwiftUI

struct FeedContentView: View {
    @Binding var isLoading: Bool
    let spots: [Spot]
    let mapSpots: [Spot]
    let selectedTab: String
    let onScrolledToBottom: () -> Void
    let onRefresh: () async -> Void
    let userId: String?
    let onDeleteSpot: (Spot) -> Void
    var onFirstItemAppeared: (() -> Void)? = nil
    @State private var firstItemRecorded = false
    @State private var failedImageSpotIds: Set<String> = []

    var body: some View {
        Group {
            if selectedTab == "Map" {
                MapView(spots: mapSpots)
                    .ignoresSafeArea(edges: .all)
            } else if isLoading && spots.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonSpotCard()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else if !spots.isEmpty {
                ScrollView {
                    RefreshControl(coordinateSpace: .named("RefreshControl")) {
                        failedImageSpotIds.removeAll()
                        Task { await onRefresh() }
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(spots.indices, id: \.self) { idx in
                            let spot = spots[idx]
                            Group {
                                if (spot.imageURL ?? "").isEmpty {
                                    SkeletonSpotCard()
                                } else {
                                    SpotCard(
                                        spot: spot,
                                        showUserInfo: true,
                                        userId: userId,
                                        onDelete: { onDeleteSpot(spot) },
                                        source: "Feed",
                                        onImageFailure: { failed in
                                            if let failedId = failed.id { failedImageSpotIds.insert(failedId) }
                                        },
                                        onImageRetry: { retrySpot in
                                            if let rid = retrySpot.id { failedImageSpotIds.remove(rid) }
                                        }
                                    )
                                }
                            }
                            .onAppear {
                                if (spot.imageURL ?? "").isEmpty {
                                    SpotLogger.error("Feed missing imageURL for spot id=\(spot.safeId) — rendering placeholder")
                                }
                                if !firstItemRecorded {
                                    onFirstItemAppeared?()
                                    firstItemRecorded = true
                                }
                                let progress = Double(idx + 1) / Double(max(spots.count, 1))
                                if progress >= 0.7 { onScrolledToBottom() }
                            }
                        }
                        if isLoading {
                            ProgressView().padding()
                        } else {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        if geo.frame(in: .global).maxY < UIScreen.main.bounds.height + 100 {
                                            onScrolledToBottom()
                                        }
                                    }
                            }
                            .frame(height: 1)
                        }
                    }
                }
                .refreshable {
                    failedImageSpotIds.removeAll()
                    await onRefresh()
                }
                .coordinateSpace(name: "RefreshControl")
                .background(Color(hex: "F5F3EF"))
            } else {
                EmptyFeedView()
            }
        }
        .background(Color(hex: "F5F3EF"))
    }
}
