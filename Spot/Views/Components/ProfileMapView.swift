//
//  ProfileMapView.swift
//  Spot
//
//  Created by Edward Wynman on 8/6/25.
//

import SwiftUI
import MapKit

struct ProfileMapView: View {
    let spots: [Spot]
    let onSpotTap: (Spot) -> Void

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: spots) { spot in
            MapAnnotation(coordinate: CLLocationCoordinate2D(
                latitude: spot.latitude ?? 0,
                longitude: spot.longitude ?? 0
            )) {
                Button(action: {
                    onSpotTap(spot)
                }) {
                    Image("green_marker")
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .preferredColorScheme(.light)
        .edgesIgnoringSafeArea(.horizontal)
        .frame(maxWidth: .infinity)
    }
}
