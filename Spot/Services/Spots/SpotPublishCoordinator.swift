//
//  SpotPublishCoordinator.swift
//  Spot
//
//  Background spot publish: Supabase Storage + Postgres (`spots` / `spot_images` / `vibe_tags`).
//

import Foundation
import SwiftUI
import UIKit

/// Serializable draft so the publish pipeline does not retain `UIImage` after the composer resets.
struct SpotPublishDraft: Equatable {
    let imageJPEGs: [Data]
    let vibeTag: String
    let latitude: Double
    let longitude: Double
    let placeName: String
    let userId: String
}

@MainActor
protocol SpotPublishing: AnyObject {
    func enqueue(draft: SpotPublishDraft, onQueued: @escaping () -> Void)
}

@MainActor
final class SpotPublishCoordinator: ObservableObject, SpotPublishing {
    static let shared = SpotPublishCoordinator()

    enum BannerPhase: Equatable {
        case hidden
        case uploading
    }

    @Published private(set) var bannerPhase: BannerPhase = .hidden
    @Published private(set) var showToast = false
    @Published private(set) var toastMessage = ""
    @Published private(set) var toastIsError = false

    private var pipelineTail: Task<Void, Never>?

    private init() {}

    func enqueue(draft: SpotPublishDraft, onQueued: @escaping () -> Void) {
        let previous = pipelineTail
        pipelineTail = Task { [weak self] in
            if let previous { await previous.value }
            guard let self else { return }
            await self.runPublish(draft: draft)
        }
        onQueued()
    }

    private func runPublish(draft: SpotPublishDraft) async {
        bannerPhase = .uploading

        guard let uid = UUID(uuidString: draft.userId) else {
            await presentErrorToast("Invalid account.")
            bannerPhase = .hidden
            return
        }

        let jpegs = draft.imageJPEGs
        guard !jpegs.isEmpty else {
            await presentErrorToast("Could not prepare images.")
            bannerPhase = .hidden
            return
        }

        do {
            let spotId = try await SpotSupabaseRepository.publishSpotFromDraft(
                userId: uid,
                imageJPEGs: jpegs,
                vibeTag: draft.vibeTag,
                latitude: draft.latitude,
                longitude: draft.longitude,
                locationName: draft.placeName
            )
            SpotLogger.log(SpotPublishCoordinatorLogs.spotPublished, details: ["spotId": spotId.uuidString])
            AnalyticsService.shared.trackUserAction("spot_posted", contentType: "spot", contentId: spotId.uuidString, parameters: [
                "vibe_tag": draft.vibeTag,
                "has_multiple_images": jpegs.count > 1
            ])
            NotificationCenter.default.post(name: .spotDidPostSuccess, object: nil)
        } catch {
            SpotLogger.log(SpotPublishCoordinatorLogs.spotUploadFailed, details: ["error": error.localizedDescription])
            await presentErrorToast(error.localizedDescription)
        }

        bannerPhase = .hidden
    }

    var bannerTitle: String {
        switch bannerPhase {
        case .hidden: return ""
        case .uploading: return "Posting your spot…"
        }
    }

    private func presentErrorToast(_ message: String) async {
        toastMessage = message
        toastIsError = true
        withAnimation { showToast = true }
        let duration: UInt64 = 2_800_000_000
        try? await Task.sleep(nanoseconds: duration)
        withAnimation { showToast = false }
    }
}
