//
//  Spot.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import Foundation
import FirebaseFirestore
import CoreLocation

struct Spot: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var username: String
    var userProfileImageURL: String?
    var imageURL: String
    var caption: String?
    var vibeTag: String
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var likes: Int = 0
    var isLiked: Bool = false
    var isSaved: Bool = false
    var timestamp: Date?
}
