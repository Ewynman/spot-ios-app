//
//  SpotUploaderLogs.swift
//  Spot
//
//  Log definitions for SpotUploader.
//

import Foundation

enum SpotUploaderLogs: SpotLog {
    // MARK: - Vibe stats
    case vibeStatIncrement
    case vibeStatFetchFailed
    case vibeStatUserDataMissing
    case vibeStatUpdateFailed
    case vibeStatUpdated

    // MARK: - User data
    case fetchUserDataFailed
    case invalidUserDataFormat

    // MARK: - Authentication
    case notAuthenticated
    case getUserDataFailed

    // MARK: - Image upload
    case imageConversionFailed
    case imageUploadStarted
    case imageUploadFailed
    case downloadURLFailed
    case downloadURLNil
    case imageUploadedGeocodingStarted
    case multiImageUploadError

    // MARK: - Spot document
    case spotCreated
    case spotCreatedMulti
    case spotDocumentCreationFailed
    case spotUpdated

    // MARK: - Cleanup
    case orphanedImageCleaned
    case orphanedImageCleanupFailed

    // MARK: - Privacy denormalization
    case authorIsPrivateDenormalizationFailed

    // MARK: - SpotLog conformance

    var tag: String { "SpotUploader" }

    var level: LogLevel {
        switch self {
        case .vibeStatIncrement:
            return .debug
        case .vibeStatFetchFailed, .vibeStatUserDataMissing, .vibeStatUpdateFailed:
            return .error
        case .vibeStatUpdated:
            return .info
        case .fetchUserDataFailed, .invalidUserDataFormat:
            return .error
        case .notAuthenticated, .getUserDataFailed:
            return .error
        case .imageConversionFailed, .imageUploadFailed, .downloadURLFailed, .downloadURLNil:
            return .error
        case .imageUploadStarted, .imageUploadedGeocodingStarted:
            return .info
        case .multiImageUploadError:
            return .error
        case .spotCreated, .spotCreatedMulti, .spotUpdated:
            return .info
        case .spotDocumentCreationFailed:
            return .error
        case .orphanedImageCleaned:
            return .info
        case .orphanedImageCleanupFailed, .authorIsPrivateDenormalizationFailed:
            return .debug
        }
    }

    var message: String {
        switch self {
        case .vibeStatIncrement:
            return "Increment vibe stat"
        case .vibeStatFetchFailed:
            return "Vibe stats: failed to get user doc"
        case .vibeStatUserDataMissing:
            return "Vibe stats: no user data"
        case .vibeStatUpdateFailed:
            return "Vibe stats update failed"
        case .vibeStatUpdated:
            return "Vibe stats updated"
        case .fetchUserDataFailed:
            return "Fetch user data failed"
        case .invalidUserDataFormat:
            return "Invalid user data format"
        case .notAuthenticated:
            return "User not authenticated for spot upload"
        case .getUserDataFailed:
            return "Get user data failed"
        case .imageConversionFailed:
            return "Image conversion failed for spot upload"
        case .imageUploadStarted:
            return "Uploading spot image to Firebase Storage"
        case .imageUploadFailed:
            return "Upload spot image failed"
        case .downloadURLFailed:
            return "Get download URL failed"
        case .downloadURLNil:
            return "Download URL nil after image upload"
        case .imageUploadedGeocodingStarted:
            return "Image uploaded; generating thumbnail and reverse geocoding"
        case .multiImageUploadError:
            return "Multi upload error"
        case .spotCreated:
            return "Spot upload success"
        case .spotCreatedMulti:
            return "Spot upload success (multi)"
        case .spotDocumentCreationFailed:
            return "Create spot document failed"
        case .spotUpdated:
            return "Spot updated"
        case .orphanedImageCleaned:
            return "Cleaned up orphaned image after document creation failure"
        case .orphanedImageCleanupFailed:
            return "Failed to clean up orphaned image"
        case .authorIsPrivateDenormalizationFailed:
            return "Failed to denormalize authorIsPrivate"
        }
    }
}
