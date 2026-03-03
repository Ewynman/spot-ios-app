//
//  PostFlowViewModel.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

class PostFlowViewModel: ObservableObject {
    @Published var currentStep = 1
    @Published var selectedImages: [UIImage] = []
    @Published var selectedLocation: LocationData?
    @Published var selectedVibe: String = ""
    @Published var isUploading = false
    @Published var isPosting = false
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastIsError = false
    @Published var showSuccessBanner = false

    var onPostSuccess: ((Spot) -> Void)?
    var onShouldDismiss: (() -> Void)?

    let totalSteps = 3

    var isEmailVerified: Bool {
        Auth.auth().currentUser?.isEmailVerified ?? false
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
        SpotLogger.debug("User went back from step \(currentStep) to step \(currentStep - 1)")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }

    func goNext() {
        guard currentStep < totalSteps else { return }
        SpotLogger.debug("User progressed from step \(currentStep) to step \(currentStep + 1)")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep += 1
        }
    }

    func submitPost() {
        guard !isPosting else { return }
        isPosting = true
        SpotLogger.info("User completed post flow")
        SpotLogger.debug("Post data - Images: \(selectedImages.count), Location: \(selectedLocation?.placeName ?? "None"), Vibe: \(selectedVibe)")

        guard let location = selectedLocation,
              !selectedVibe.isEmpty,
              !location.placeName.isEmpty,
              location.coordinate.latitude != 0,
              location.coordinate.longitude != 0
        else {
            showToastWith(message: "All fields are required to post a spot.", isError: true)
            isPosting = false
            return
        }

        isUploading = true
        let imagesToUpload = selectedImages
        let vibe = selectedVibe
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let placeName = location.placeName

        if imagesToUpload.count <= 1, let image = imagesToUpload.first {
            SpotUploader.shared.uploadSpot(
                image: image,
                vibeTag: vibe,
                latitude: lat,
                longitude: lon,
                placeName: placeName
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isUploading = false
                    switch result {
                    case .success:
                        if let userId = Auth.auth().currentUser?.uid {
                            SpotUploader.incrementUserVibeStat(userId: userId, vibeTag: vibe)
                        }
                        Task { await self?.awaitModerationAndFinish() }
                    case .failure(let error):
                        self?.showToastWith(message: error.localizedDescription, isError: true)
                        SpotLogger.error("Spot upload failed: \(error.localizedDescription)")
                        self?.isPosting = false
                    }
                }
            }
            return
        }

        SpotUploader.shared.uploadSpot(
            images: imagesToUpload,
            vibeTag: vibe,
            latitude: lat,
            longitude: lon,
            placeName: placeName
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isUploading = false
                switch result {
                case .success:
                    if let userId = Auth.auth().currentUser?.uid {
                        SpotUploader.incrementUserVibeStat(userId: userId, vibeTag: vibe)
                    }
                    Task { await self?.awaitModerationAndFinish() }
                case .failure(let error):
                    self?.showToastWith(message: error.localizedDescription, isError: true)
                    SpotLogger.error("Spot upload failed: \(error.localizedDescription)")
                    self?.isPosting = false
                }
            }
        }
    }

    private func awaitModerationAndFinish() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run { isPosting = false }
            return
        }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("spots")
                .whereField("userId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first else {
                await MainActor.run { isPosting = false }
                return
            }
            let spotRef = doc.reference
            SpotLogger.info("Moderation.Check.Begin spotId=\(doc.documentID)")

            for _ in 0..<20 {
                let latest = try await spotRef.getDocument()
                if await evaluateModeration(doc: latest) { return }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            SpotLogger.error("Moderation check timeout", details: ["spotId": doc.documentID])
            await MainActor.run {
                showToastWith(message: "We couldn't verify your image yet. Please retry.", isError: true)
                isPosting = false
            }
        } catch {
            SpotLogger.error("Moderation gate error: \(error.localizedDescription)")
            await MainActor.run { isPosting = false }
        }
    }

    private func evaluateModeration(doc: DocumentSnapshot) async -> Bool {
        let data = doc.data() ?? [:]
        let moderation = data["moderation"] as? [String: Any]
        let status = moderation?["status"] as? String ?? "pending"
        let scores = moderation?["scores"] as? [String: Any]

        if status == "approved" {
            let (ok, reason) = ModerationPolicy.evaluate(scores: scores)
            if ok {
                SpotLogger.info("Moderation.Check.Approved spotId=\(doc.documentID) scores=\(String(describing: scores))")
                if var spot = try? doc.data(as: Spot.self) {
                    spot.id = doc.documentID
                    await MainActor.run {
                        AnalyticsService.shared.trackUserAction("spot_posted", contentType: "spot", contentId: doc.documentID, parameters: [
                            "vibe_tag": spot.vibeTag ?? "",
                            "has_multiple_images": (spot.imageURLs?.count ?? 0) > 1
                        ])
                        onPostSuccess?(spot)
                        isPosting = false
                        onShouldDismiss?()
                    }
                } else {
                    await MainActor.run {
                        AnalyticsService.shared.trackUserAction("spot_posted", contentType: "spot", contentId: doc.documentID)
                        onPostSuccess?(Spot(id: doc.documentID))
                        isPosting = false
                        onShouldDismiss?()
                    }
                }
                return true
            } else {
                SpotLogger.error("Post blocked by moderation", details: ["reason": reason ?? "over_threshold", "spotId": doc.documentID])
                await MainActor.run {
                    showToastWith(message: "This photo violates our guidelines and can't be posted.", isError: true)
                    isPosting = false
                }
                return true
            }
        } else if status == "rejected" {
            SpotLogger.error("Moderation check rejected", details: ["spotId": doc.documentID, "scores": String(describing: scores)])
            try? await doc.reference.delete()
            await MainActor.run {
                showToastWith(message: "This photo violates our guidelines and can't be posted.", isError: true)
                isPosting = false
            }
            return true
        } else {
            SpotLogger.debug("Moderation.Check.Pending spotId=\(doc.documentID)")
            return false
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
}
