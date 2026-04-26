import Foundation
import UIKit
import CoreLocation

enum PostComposerDraftStatus: String, Codable {
    case autosaved
    case saved
}

enum PostComposerDraftStep: String, Codable {
    case photos
    case location
    case vibes
}

struct PostComposerDraftSummary: Codable, Identifiable, Equatable {
    let id: String
    let status: PostComposerDraftStatus
    let previewImageFileName: String?
    let placeName: String?
    let vibeTags: [String]
    let updatedAt: Date
    let step: PostComposerDraftStep
}

struct PostComposerDraft: Codable, Identifiable {
    let id: String
    let step: Int
    let status: PostComposerDraftStatus
    let vibeTags: [String]
    let latitude: Double?
    let longitude: Double?
    let placeName: String?
    let address: String?
    let isCustomName: Bool
    let imageFileNames: [String]
    let updatedAt: Date
}

enum PostDraftStore {
    private static let draftIndexFileName = "post-composer-drafts-index.json"
    private static let autosavedDraftID = "autosave"

    private static var draftsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("PostDrafts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                SpotLogger.log(PostDraftStoreLogs.draftsDirectoryCreateFailed, details: ["error": error.localizedDescription])
            }
        }
        return dir
    }

    private static var draftIndexURL: URL {
        draftsDirectory.appendingPathComponent(draftIndexFileName)
    }

    private static func draftFileURL(for draftID: String) -> URL {
        draftsDirectory.appendingPathComponent("post-composer-draft-\(draftID).json")
    }

    private static func imageFileName(draftID: String, index: Int) -> String {
        "draft_\(draftID)_image_\(index).jpg"
    }

    private static func loadIndex() -> [PostComposerDraftSummary] {
        guard let raw = try? Data(contentsOf: draftIndexURL) else {
            return []
        }
        guard let decoded = try? JSONDecoder().decode([PostComposerDraftSummary].self, from: raw) else {
            SpotLogger.log(PostDraftStoreLogs.draftIndexDecodeFailed)
            return []
        }
        return decoded.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private static func saveIndex(_ summaries: [PostComposerDraftSummary]) {
        guard let encoded = try? JSONEncoder().encode(summaries) else {
            SpotLogger.log(PostDraftStoreLogs.draftIndexEncodeFailed, details: ["stage": "encode"])
            return
        }
        do {
            try encoded.write(to: draftIndexURL, options: .atomic)
        } catch {
            SpotLogger.log(PostDraftStoreLogs.draftIndexEncodeFailed, details: ["stage": "write", "error": error.localizedDescription])
        }
    }

    static func listDrafts() -> [PostComposerDraftSummary] {
        loadIndex()
    }

    static func save(
        step: Int,
        images: [UIImage],
        selectedLocation: LocationData?,
        selectedVibes: [String],
        draftID: String? = nil,
        status: PostComposerDraftStatus = .autosaved
    ) -> String {
        let resolvedID = draftID ?? (status == .autosaved ? autosavedDraftID : UUID().uuidString)
        deleteImageFiles(for: resolvedID)

        var imageNames: [String] = []
        for (index, image) in images.enumerated() {
            let fileName = imageFileName(draftID: resolvedID, index: index)
            let url = draftsDirectory.appendingPathComponent(fileName)
            guard let data = image.jpegData(compressionQuality: 0.78) else { continue }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                SpotLogger.log(PostDraftStoreLogs.draftImageWriteFailed, details: [
                    "draftId": resolvedID,
                    "fileName": fileName,
                    "error": error.localizedDescription
                ])
                continue
            }
            imageNames.append(fileName)
        }

        let draft = PostComposerDraft(
            id: resolvedID,
            step: step,
            status: status,
            vibeTags: selectedVibes,
            latitude: selectedLocation?.coordinate.latitude,
            longitude: selectedLocation?.coordinate.longitude,
            placeName: selectedLocation?.placeName,
            address: selectedLocation?.address,
            isCustomName: selectedLocation?.isCustomName ?? false,
            imageFileNames: imageNames,
            updatedAt: Date()
        )

        if let encoded = try? JSONEncoder().encode(draft) {
            do {
                try encoded.write(to: draftFileURL(for: resolvedID), options: .atomic)
            } catch {
                SpotLogger.log(PostDraftStoreLogs.draftWriteFailed, details: ["draftId": resolvedID, "error": error.localizedDescription])
            }
        } else {
            SpotLogger.log(PostDraftStoreLogs.draftWriteFailed, details: ["draftId": resolvedID, "error": "encode_failed"])
        }

        upsertSummary(for: draft)
        return resolvedID
    }

    static func loadDraft(id: String) -> (draft: PostComposerDraft, images: [UIImage], location: LocationData?)? {
        guard let raw = try? Data(contentsOf: draftFileURL(for: id)) else {
            SpotLogger.log(PostDraftStoreLogs.draftReadFailed, details: ["draftId": id])
            return nil
        }
        guard let draft = try? JSONDecoder().decode(PostComposerDraft.self, from: raw) else {
            SpotLogger.log(PostDraftStoreLogs.draftDecodeFailed, details: ["draftId": id])
            return nil
        }

        let images: [UIImage] = draft.imageFileNames.compactMap { fileName in
            let url = draftsDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else {
                SpotLogger.log(PostDraftStoreLogs.draftImageReadFailed, details: ["draftId": id, "fileName": fileName, "reason": "data_read_failed"])
                return nil
            }
            guard let image = UIImage(data: data) else {
                SpotLogger.log(PostDraftStoreLogs.draftImageReadFailed, details: ["draftId": id, "fileName": fileName, "reason": "image_decode_failed"])
                return nil
            }
            return image
        }

        var location: LocationData?
        if
            let lat = draft.latitude,
            let lon = draft.longitude,
            let placeName = draft.placeName
        {
            location = LocationData(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                placeName: placeName,
                address: draft.address,
                isCustomName: draft.isCustomName
            )
        }

        return (draft, images, location)
    }

    static func loadAutosavedDraft() -> (draft: PostComposerDraft, images: [UIImage], location: LocationData?)? {
        loadDraft(id: autosavedDraftID)
    }

    static func loadPreviewImage(fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        let url = draftsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return image
    }

    static func deleteDraft(id: String) {
        if let draft = (try? Data(contentsOf: draftFileURL(for: id))).flatMap({ try? JSONDecoder().decode(PostComposerDraft.self, from: $0) }) {
            for fileName in draft.imageFileNames {
                let url = draftsDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
        }
        try? FileManager.default.removeItem(at: draftFileURL(for: id))

        var summaries = loadIndex()
        summaries.removeAll { $0.id == id }
        saveIndex(summaries)
        SpotLogger.log(PostDraftStoreLogs.draftDeleted, details: ["draftId": id])
    }

    static func clearAutosave() {
        deleteDraft(id: autosavedDraftID)
    }

    static func clearAll() {
        for draft in loadIndex() {
            deleteDraft(id: draft.id)
        }
    }
}

private extension PostDraftStore {
    static func deleteImageFiles(for draftID: String) {
        guard
            let raw = try? Data(contentsOf: draftFileURL(for: draftID)),
            let existing = try? JSONDecoder().decode(PostComposerDraft.self, from: raw)
        else { return }

        for fileName in existing.imageFileNames {
            try? FileManager.default.removeItem(at: draftsDirectory.appendingPathComponent(fileName))
        }
    }

    static func upsertSummary(for draft: PostComposerDraft) {
        let step: PostComposerDraftStep = switch draft.step {
        case 1: .photos
        case 2: .location
        default: .vibes
        }
        let summary = PostComposerDraftSummary(
            id: draft.id,
            status: draft.status,
            previewImageFileName: draft.imageFileNames.first,
            placeName: draft.placeName,
            vibeTags: draft.vibeTags,
            updatedAt: draft.updatedAt,
            step: step
        )

        var summaries = loadIndex()
        summaries.removeAll { $0.id == draft.id }
        summaries.append(summary)
        summaries.sort(by: { $0.updatedAt > $1.updatedAt })
        saveIndex(summaries)
    }
}
