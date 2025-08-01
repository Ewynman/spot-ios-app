import SwiftUI
import MapKit
import CoreLocation

struct LocationSelectionView: View {
    @Binding var selectedLocation: LocationData?
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var nearbyPlaces: [MKMapItem] = []
    @State private var currentLocation: CLLocation?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var showingMap = false
    @State private var isSearching = false
    @State private var isLoadingNearby = true
    
    private let locationManager = CLLocationManager()
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Select Your Spot's Location")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)
                
                Text("Search for a place or select from nearby locations")
                    .font(FontManager.primaryText())
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search for a place...", text: $searchText)
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.primary)
                    .onChange(of: searchText) { newValue in
                        searchPlaces(query: newValue)
                    }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Constants.Colors.primary, lineWidth: 1)
            )
            .padding(.horizontal, 32)
            
            // Content based on search
            if !searchText.isEmpty && !searchResults.isEmpty {
                // Search Results
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Results")
                        .font(FontManager.primaryText())
                        .fontWeight(.semibold)
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 32)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults, id: \.self) { item in
                                LocationResultRow(item: item) { location in
                                    selectedLocation = location
                                    showingMap = true
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            } else {
                // Nearby Places
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby Places")
                        .font(FontManager.primaryText())
                        .fontWeight(.semibold)
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 32)
                    
                    if isLoadingNearby {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.0)
                            Spacer()
                        }
                        .frame(height: 100)
                    } else if nearbyPlaces.isEmpty {
                        Text("No nearby places found")
                            .font(FontManager.primaryText())
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(nearbyPlaces, id: \.self) { item in
                                    NearbyPlaceRow(item: item) { location in
                                        selectedLocation = location
                                        showingMap = true
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
            
            // Selected Location Preview
            if let location = selectedLocation {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Constants.Colors.primary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.placeName)
                                .font(FontManager.primaryText())
                                .fontWeight(.semibold)
                                .foregroundColor(Constants.Colors.primary)
                            
                            if let address = location.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Change") {
                            selectedLocation = nil
                        }
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Constants.Colors.primary, lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                }
            }
            
            Spacer()
        }
        .onAppear {
            setupLocationManager()
            loadNearbyPlaces()
        }
        .sheet(isPresented: $showingMap) {
            LocationMapView(location: selectedLocation!, onConfirm: { location in
                selectedLocation = location
                showingMap = false
            })
        }
    }
    
    private func setupLocationManager() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func loadNearbyPlaces() {
        SpotLogger.debug("Loading nearby places")
        guard let location = locationManager.location else {
            SpotLogger.warning("No current location available, using default region")
            // If no location, use default region
            searchNearbyPlaces(in: region)
            return
        }
        
        SpotLogger.info("Got current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        // Update region to current location
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        // Search for nearby places
        searchNearbyPlaces(in: region)
    }
    
    private func searchNearbyPlaces(in region: MKCoordinateRegion) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant cafe bar park"
        request.region = region
        request.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isLoadingNearby = false
                if let error = error {
                    SpotLogger.error("Failed to search nearby places: \(error.localizedDescription)")
                } else if let response = response {
                    SpotLogger.info("Found \(response.mapItems.count) nearby places")
                    self.nearbyPlaces = Array(response.mapItems.prefix(10)) // Limit to 10 nearby places
                }
            }
        }
    }
    
    private func searchPlaces(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        SpotLogger.debug("Searching for places with query: \(query)")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                if let error = error {
                    SpotLogger.error("Failed to search places: \(error.localizedDescription)")
                } else if let response = response {
                    SpotLogger.info("Found \(response.mapItems.count) search results for '\(query)'")
                    self.searchResults = response.mapItems
                }
            }
        }
    }
}

// MARK: - Location Result Row
struct LocationResultRow: View {
    let item: MKMapItem
    let onSelect: (LocationData) -> Void
    
    var body: some View {
        Button(action: {
            let locationData = LocationData(
                coordinate: item.placemark.coordinate,
                placeName: item.name ?? "Unknown Location",
                address: item.placemark.thoroughfare
            )
            SpotLogger.info("User selected location: \(locationData.placeName)")
            onSelect(locationData)
        }) {
            HStack(spacing: 12) {
                Image("green_marker")
                    .resizable()
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unknown Location")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                    
                    if let address = item.placemark.thoroughfare {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Nearby Place Row
struct NearbyPlaceRow: View {
    let item: MKMapItem
    let onSelect: (LocationData) -> Void
    
    var body: some View {
        Button(action: {
            let locationData = LocationData(
                coordinate: item.placemark.coordinate,
                placeName: item.name ?? "Unknown Location",
                address: item.placemark.thoroughfare
            )
            SpotLogger.info("User selected location: \(locationData.placeName)")
            onSelect(locationData)
        }) {
            HStack(spacing: 12) {
                Image("green_marker")
                    .resizable()
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unknown Location")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                    
                    if let address = item.placemark.thoroughfare {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Location Map View
struct LocationMapView: View {
    let location: LocationData
    let onConfirm: (LocationData) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var region: MKCoordinateRegion
    @State private var draggedLocation: LocationData
    @State private var centerCoordinate: CLLocationCoordinate2D
    
    init(location: LocationData, onConfirm: @escaping (LocationData) -> Void) {
        self.location = location
        self.onConfirm = onConfirm
        self._region = State(initialValue: MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        self._draggedLocation = State(initialValue: location)
        self._centerCoordinate = State(initialValue: location.coordinate)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, annotationItems: [draggedLocation]) { location in
                    MapAnnotation(coordinate: location.coordinate) {
                        Image("green_marker")
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                }
                .onChange(of: region.center.latitude) { _ in
                    updateDraggedLocation()
                }
                .onChange(of: region.center.longitude) { _ in
                    updateDraggedLocation()
                }
                
                VStack {
                    Spacer()
                    
                    Button("Confirm Location") {
                        onConfirm(draggedLocation)
                    }
                    .font(FontManager.buttonText())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Constants.Colors.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Confirm Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateDraggedLocation() {
        let newCoordinate = region.center
        
        // Reverse geocode the new coordinate to get the actual location name
        let location = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // Create a more descriptive place name
                    var placeName = ""
                    
                    if let name = placemark.name {
                        placeName = name
                    } else if let thoroughfare = placemark.thoroughfare {
                        placeName = thoroughfare
                        if let subThoroughfare = placemark.subThoroughfare {
                            placeName = "\(subThoroughfare) \(placeName)"
                        }
                    } else if let locality = placemark.locality {
                        placeName = locality
                        if let administrativeArea = placemark.administrativeArea {
                            placeName = "\(placeName), \(administrativeArea)"
                        }
                    } else if let administrativeArea = placemark.administrativeArea {
                        placeName = administrativeArea
                    }
                    
                    // Create address string
                    var addressComponents: [String] = []
                    if let thoroughfare = placemark.thoroughfare {
                        addressComponents.append(thoroughfare)
                    }
                    if let locality = placemark.locality {
                        addressComponents.append(locality)
                    }
                    if let administrativeArea = placemark.administrativeArea {
                        addressComponents.append(administrativeArea)
                    }
                    let address = addressComponents.joined(separator: ", ")
                    
                    self.draggedLocation = LocationData(
                        coordinate: newCoordinate,
                        placeName: placeName.isEmpty ? "Selected Location" : placeName,
                        address: address.isEmpty ? nil : address
                    )
                } else {
                    // Fallback if geocoding fails
                    self.draggedLocation = LocationData(
                        coordinate: newCoordinate,
                        placeName: "Selected Location",
                        address: nil
                    )
                }
            }
        }
    }
}

#Preview {
    LocationSelectionView(selectedLocation: .constant(nil))
} 