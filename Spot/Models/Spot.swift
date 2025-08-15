//
//  Spot.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import CoreLocation

struct Spot: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?
    var userId: String?
    var username: String?
    var userProfileImageURL: String?
    var imageURL: String?
    var thumbnailURL: String?
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
    
    static func fromDocument(_ document: QueryDocumentSnapshot) async throws -> Spot? {
        do {
            var spot = try document.data(as: Spot.self)
            
            // If we have location data, format it as City, State
            if let latitude = spot.latitude,
               let longitude = spot.longitude {
                let location = CLLocation(latitude: latitude, longitude: longitude)
                let geocoder = CLGeocoder()
                
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    if let placemark = placemarks.first,
                       let city = placemark.locality,
                       let state = placemark.administrativeArea {
                        spot.locationName = "\(city), \(state)"
                    }
                } catch {
                    SpotLogger.error("Geocoding failed for spot: \(error.localizedDescription)")
                }
            }
            
            return spot
        } catch {
            SpotLogger.error("Failed to decode spot: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func == (lhs: Spot, rhs: Spot) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
