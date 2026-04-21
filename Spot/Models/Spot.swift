//
//  Spot.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import CoreLocation

struct Spot: Identifiable, Codable, Equatable, Hashable {
    var id: String?
    var userId: String?
    var username: String?
    var userProfileImageURL: String?
    var imageURL: String?
    var thumbnailURL: String?
    var imageURLs: [String]?
    var vibeTag: String?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var likes: Int?
    var isLiked: Bool?
    var isSaved: Bool?
    var createdAt: Date?
    // Optional denormalized snapshot to enable quick pre-filtering.
    var authorIsPrivate: Bool?

    // Explicit initializer to preserve source compatibility for existing call sites
    init(
        id: String? = nil,
        userId: String? = nil,
        username: String? = nil,
        userProfileImageURL: String? = nil,
        imageURL: String? = nil,
        thumbnailURL: String? = nil,
        vibeTag: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        likes: Int? = nil,
        isLiked: Bool? = nil,
        isSaved: Bool? = nil,
        createdAt: Date? = nil,
        authorIsPrivate: Bool? = nil,
        imageURLs: [String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.username = username
        self.userProfileImageURL = userProfileImageURL
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.imageURLs = imageURLs
        self.vibeTag = vibeTag
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.likes = likes
        self.isLiked = isLiked
        self.isSaved = isSaved
        self.createdAt = createdAt
        self.authorIsPrivate = authorIsPrivate
    }

    static func withResolvedLocation(_ spot: Spot) async -> Spot {
        var spot = spot
        let hasCustomLocation = !(spot.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasCustomLocation, let latitude = spot.latitude, let longitude = spot.longitude {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    if let name = placemark.name, !name.isEmpty {
                        spot.locationName = name
                    } else if let city = placemark.locality, let state = placemark.administrativeArea {
                        spot.locationName = "\(city), \(state)"
                    }
                }
            } catch {
                SpotLogger.log(SpotModelLogs.geocodingFailed, details: ["error": error.localizedDescription])
            }
        }
        return spot
    }

    static func == (lhs: Spot, rhs: Spot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
