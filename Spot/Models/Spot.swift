//
//  Spot.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import CoreLocation

struct Spot: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var userId: String?
    var username: String?
    var userProfileImageURL: String?
    var imageURL: String?
    var caption: String?
    var vibeTag: String?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var likes: Int?
    var isLiked: Bool?
    var isSaved: Bool?
    var createdAt: Date?
    
    static func == (lhs: Spot, rhs: Spot) -> Bool {
        // Compare all relevant fields
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.username == rhs.username &&
               lhs.userProfileImageURL == rhs.userProfileImageURL &&
               lhs.imageURL == rhs.imageURL &&
               lhs.caption == rhs.caption &&
               lhs.vibeTag == rhs.vibeTag &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.locationName == rhs.locationName &&
               lhs.likes == rhs.likes &&
               lhs.isLiked == rhs.isLiked &&
               lhs.isSaved == rhs.isSaved &&
               lhs.createdAt == rhs.createdAt
    }
}
