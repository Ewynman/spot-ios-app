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
                    .onChange(of: searchText) { _, newValue in
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
                        .buttonStyle(PlainButtonStyle())
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
            let city = item.placemark.locality
            let state = item.placemark.administrativeArea
            let country = item.placemark.country
            let parts = [city, state, country].compactMap { $0 }.joined(separator: ", ")
            let locationData = LocationData(
                coordinate: item.placemark.coordinate,
                placeName: item.name ?? (city ?? state ?? country ?? "Unknown Location"),
                address: parts.isEmpty ? nil : parts
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
                    let city = item.placemark.locality
                    let state = item.placemark.administrativeArea
                    let country = item.placemark.country
                    let parts = [city, state, country].compactMap { $0 }.joined(separator: ", ")
                    if !parts.isEmpty {
                        Text(parts)
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
            let city = item.placemark.locality
            let state = item.placemark.administrativeArea
            let country = item.placemark.country
            let parts = [city, state, country].compactMap { $0 }.joined(separator: ", ")
            let locationData = LocationData(
                coordinate: item.placemark.coordinate,
                placeName: item.name ?? (city ?? state ?? country ?? "Unknown Location"),
                address: parts.isEmpty ? nil : parts
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
                    let city = item.placemark.locality
                    let state = item.placemark.administrativeArea
                    let country = item.placemark.country
                    let parts = [city, state, country].compactMap { $0 }.joined(separator: ", ")
                    if !parts.isEmpty {
                        Text(parts)
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
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var draggedLocation: LocationData
    @State private var currentLocationName: String
    @State private var geocodeWorkItem: DispatchWorkItem?
    private let geocoder = CLGeocoder()
    @State private var isGeocoding = false
    @State private var allowConfirmDespiteGeocoding = false

    init(location: LocationData, onConfirm: @escaping (LocationData) -> Void) {
        self.location = location
        self.onConfirm = onConfirm
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        _position = State(initialValue: .region(region))
        _draggedLocation = State(initialValue: location)
        _currentLocationName = State(initialValue: location.placeName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    // Blue dot (appears when permission granted)
                    UserAnnotation()

                    // Your custom “green_marker” pin
                    Annotation("", coordinate: draggedLocation.coordinate, anchor: .bottom) {
                        Image("green_marker")
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                }
                // Get notified when the user pans/zooms and update the selection
                .onMapCameraChange(frequency: .onEnd) { context in
                    let center = context.region.center
                    updateDraggedLocation(to: center)
                }
                .preferredColorScheme(.light)

                // Top “current name” chip
                VStack {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Constants.Colors.primary)
                        Text(currentLocationName)
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    // Confirm
                    Button("Confirm Location") {
                        onConfirm(draggedLocation)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(FontManager.buttonText())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Constants.Colors.primary)
                    .cornerRadius(20)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .disabled(isGeocoding && !allowConfirmDespiteGeocoding)

                }
                // Handy built-in controls
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        MapUserLocationButton()
                        MapCompass()
                        MapPitchToggle()
                        MapScaleView()
                    }
                    .padding()
                }
            }
            .navigationTitle("Confirm Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Reverse geocode the new center (debounced)
    private func updateDraggedLocation(to newCenter: CLLocationCoordinate2D) {
        draggedLocation = LocationData(
            coordinate: newCenter,
            placeName: draggedLocation.placeName,
            address: draggedLocation.address
        )

        geocodeWorkItem?.cancel()
        isGeocoding = true
        allowConfirmDespiteGeocoding = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isGeocoding {
                self.allowConfirmDespiteGeocoding = true
                SpotLogger.warning("Reverse geocode timeout reached; allowing confirm.")
            }
        }

        let work = DispatchWorkItem { [newCenter] in
            let loc = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
            self.geocoder.cancelGeocode()
            self.geocoder.reverseGeocodeLocation(loc) { placemarks, error in
                DispatchQueue.main.async {
                    if let error = error as NSError? {
                        SpotLogger.warning("Reverse geocode failed: \(error.localizedDescription)")
                        self.isGeocoding = false
                        return
                    }
                    guard let placemark = placemarks?.first else {
                        self.isGeocoding = false
                        return
                    }
                    let city = placemark.locality
                    let state = placemark.administrativeArea
                    let country = placemark.country
                    let display = [city, state].compactMap { $0 }.joined(separator: ", ")
                    let address = [city, state, country].compactMap { $0 }.joined(separator: ", ")

                    let prettyName = display.isEmpty ? (placemark.name ?? self.draggedLocation.placeName) : display
                    self.draggedLocation = LocationData(
                        coordinate: newCenter,
                        placeName: prettyName,
                        address: address.isEmpty ? nil : address
                    )
                    self.currentLocationName = prettyName
                    self.isGeocoding = false
                    self.allowConfirmDespiteGeocoding = false
                }
            }
        }
        geocodeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

#Preview {
    LocationSelectionView(selectedLocation: .constant(nil))
} 
