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
    var imageURL: String
    var latitude: Double
    var longitude: Double
    var vibeTag: String
    var timestamp: Date?
}
