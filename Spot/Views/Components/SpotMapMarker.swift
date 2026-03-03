//
//  SpotMapMarker.swift
//  Spot
//
//  Created By: Wynman, Edward
//  Date: 03/02/2025
//

import SwiftUI
import MapKit

struct SpotAnnotation: Identifiable {
    let id = UUID()
    let spot: Spot
    let coordinate: CLLocationCoordinate2D

    init(spot: Spot) {
        self.spot = spot
        self.coordinate = CLLocationCoordinate2D(
            latitude: spot.latitude ?? 0.0,
            longitude: spot.longitude ?? 0.0
        )
    }
}

struct SpotMapMarker: View {
    let spot: Spot
    var body: some View {
        Image("green_marker")
            .resizable()
            .frame(width: 20, height: 20)
    }
}
