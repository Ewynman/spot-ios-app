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
    /// True only while JPEG-encoding and handing off to `SpotPublishCoordinator` (brief).
    @Published var isEncodingPost = false
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastIsError = false
    @Published var showSuccessBanner = false

    /// Called on the main thread immediately after a publish job is queued (e.g. switch to Home tab).
    var onPostQueued: (() -> Void)?

    /// Injected by PostFlowView from environment; used instead of Auth.auth().
    weak var authViewModel: AuthViewModel?

    /// Override in tests; production uses `SpotPublishCoordinator.shared`.
    var spotPublisher: SpotPublishing = SpotPublishCoordinator.shared

    let totalSteps = 3

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
        case 3: return !selectedVibe.isEmpty
        default: return false
        }
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
              !selectedVibe.isEmpty,
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

        isEncodingPost = true
        let vibe = selectedVibe
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
                vibeTag: vibe,
                latitude: lat,
                longitude: lon,
                placeName: placeName,
                userId: userId
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
}
