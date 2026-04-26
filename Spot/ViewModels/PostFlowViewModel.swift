//
//  PostFlowViewModel.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation
import SwiftUI
import UIKit

@MainActor
class PostFlowViewModel: ObservableObject {
    @Published var currentStep = 1
    @Published var selectedImages: [UIImage] = []
    @Published var selectedLocation: LocationData?
    @Published var selectedVibe: String = ""
    @Published var selectedVibes: [String] = []
    /// True only while JPEG-encoding and handing off to `SpotPublishCoordinator` (brief).
    @Published var isEncodingPost = false
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastIsError = false
    @Published var showSuccessBanner = false
    @Published var availableDrafts: [PostComposerDraftSummary] = []
    @Published var activeDraftID: String?

    /// Called on the main thread immediately after a publish job is queued (e.g. switch to Home tab).
    var onPostQueued: (() -> Void)?

    /// Injected by PostFlowView from environment; used instead of Auth.auth().
    weak var authViewModel: AuthViewModel?

    /// Override in tests; production uses `SpotPublishCoordinator.shared`.
    var spotPublisher: SpotPublishing = SpotPublishCoordinator.shared

    let totalSteps = 3
    private let genericPostFailureMessage = "Error Posting Spot Try Again Later"

    var isEmailVerified: Bool {
        authViewModel?.isEmailVerified ?? false
    }

    private var currentUserId: String? {
        authViewModel?.userId
    }

    var canProceedToNextStep: Bool {
        switch currentStep {
        case 1: return !selectedImages.isEmpty
        case 2: return selectedLocation != nil
        case 3: return !selectedVibes.isEmpty
        default: return false
        }
    }

    var canSaveDraft: Bool {
        !selectedImages.isEmpty || selectedLocation != nil || !selectedVibes.isEmpty
    }

    var canSubmitPost: Bool {
        !selectedImages.isEmpty && selectedLocation != nil && !selectedVibes.isEmpty
    }

    func goBack() {
        guard currentStep > 1 else { return }
        SpotLogger.log(PostFlowViewModelLogs.userWentBack, details: ["from": currentStep, "to": currentStep - 1])
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }

    func goNext() {
        guard currentStep < totalSteps else { return }
        SpotLogger.log(PostFlowViewModelLogs.userProgressed, details: ["from": currentStep, "to": currentStep + 1])
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep += 1
        }
    }

    func submitPost() {
        guard !isEncodingPost else { return }
        SpotLogger.log(PostFlowViewModelLogs.userCompletedPostFlow)
        SpotLogger.log(PostFlowViewModelLogs.postData, details: ["images": selectedImages.count, "location": selectedLocation?.placeName ?? "None", "vibe": selectedVibe])

        guard let location = selectedLocation,
              !selectedVibes.isEmpty,
              !location.placeName.isEmpty,
              location.coordinate.latitude != 0,
              location.coordinate.longitude != 0
        else {
            showToastWith(message: "All fields are required to post a spot.", isError: true)
            return
        }

        guard let userId = currentUserId, !userId.isEmpty else {
            showToastWith(message: "You need to be signed in to post.", isError: true)
            return
        }

        persistDraftSnapshot()
        VibeTagUsageStore.recordUsage(tags: selectedVibes)

        isEncodingPost = true
        let vibes = selectedVibes
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let placeName = location.placeName
        let images = selectedImages

        Task { [weak self] in
            guard let self else { return }
            guard let jpegs = await self.encodeImagesForUpload(images), !jpegs.isEmpty else {
                self.showToastWith(message: "Could not prepare images. Try different photos.", isError: true)
                self.isEncodingPost = false
                return
            }

            let draft = SpotPublishDraft(
                imageJPEGs: jpegs,
                vibeTags: vibes,
                latitude: lat,
                longitude: lon,
                placeName: placeName,
                userId: userId,
                sourceDraftID: self.activeDraftID
            )

            self.spotPublisher.enqueue(draft: draft) { [weak self] in
                guard let self else { return }
                self.resetComposerAfterQueued()
                self.onPostQueued?()
                self.isEncodingPost = false
            }
        }
    }

    private func resetComposerAfterQueued() {
        selectedImages = []
        selectedLocation = nil
        selectedVibe = ""
        selectedVibes = []
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = 1
        }
    }

    func showToastWith(message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation { self?.showToast = false }
        }
    }

    func persistDraftSnapshot() {
        activeDraftID = PostDraftStore.save(
            step: currentStep,
            images: selectedImages,
            selectedLocation: selectedLocation,
            selectedVibes: selectedVibes,
            draftID: activeDraftID,
            status: .autosaved
        )
        refreshDrafts()
    }

    func loadPersistedDraftIfAvailable() -> Bool {
        guard let loaded = PostDraftStore.loadAutosavedDraft() else { return false }
        selectedImages = loaded.images
        selectedLocation = loaded.location
        selectedVibes = loaded.draft.vibeTags
        selectedVibe = loaded.draft.vibeTags.first ?? ""
        currentStep = min(max(loaded.draft.step, 1), totalSteps)
        activeDraftID = loaded.draft.id
        refreshDrafts()
        return true
    }

    func clearPersistedDraft() {
        if let activeDraftID {
            PostDraftStore.deleteDraft(id: activeDraftID)
            self.activeDraftID = nil
        } else {
            PostDraftStore.clearAutosave()
        }
        refreshDrafts()
    }

    func handlePublishFailure() {
        showToastWith(message: genericPostFailureMessage, isError: true)
        persistDraftSnapshot()
    }

    private func encodeImagesForUpload(_ images: [UIImage]) async -> [Data]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var output: [Data] = []
                output.reserveCapacity(images.count)
                for image in images {
                    let data = autoreleasepool(invoking: { image.jpegData(compressionQuality: 0.78) })
                    guard let data else {
                        continuation.resume(returning: nil)
                        return
                    }
                    output.append(data)
                }
                continuation.resume(returning: output)
            }
        }
    }

    func refreshDrafts() {
        availableDrafts = PostDraftStore.listDrafts()
    }

    @discardableResult
    func saveDraftManually() -> Bool {
        guard canSaveDraft else {
            showToastWith(message: "Add photos, location, or vibes before saving.", isError: true)
            return false
        }
        activeDraftID = PostDraftStore.save(
            step: currentStep,
            images: selectedImages,
            selectedLocation: selectedLocation,
            selectedVibes: selectedVibes,
            draftID: activeDraftID == "autosave" ? nil : activeDraftID,
            status: .saved
        )
        VibeTagUsageStore.recordUsage(tags: selectedVibes)
        PostDraftStore.clearAutosave()
        resetComposerForDraftExit()
        refreshDrafts()
        showToastWith(message: "Draft saved", isError: false)
        return true
    }

    func resumeDraft(id: String) {
        guard let loaded = PostDraftStore.loadDraft(id: id) else {
            showToastWith(message: "Could not open that draft.", isError: true)
            return
        }
        selectedImages = loaded.images
        selectedLocation = loaded.location
        selectedVibes = loaded.draft.vibeTags
        selectedVibe = loaded.draft.vibeTags.first ?? ""
        currentStep = min(max(loaded.draft.step, 1), totalSteps)
        activeDraftID = loaded.draft.id
        refreshDrafts()
    }

    func deleteDraft(id: String) {
        PostDraftStore.deleteDraft(id: id)
        if activeDraftID == id {
            activeDraftID = nil
        }
        refreshDrafts()
    }

    private func resetComposerForDraftExit() {
        selectedImages = []
        selectedLocation = nil
        selectedVibe = ""
        selectedVibes = []
        currentStep = 1
        activeDraftID = nil
    }
}
