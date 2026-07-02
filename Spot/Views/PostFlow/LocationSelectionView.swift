import SwiftUI
import MapKit
import CoreLocation
import UIKit

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
    @State private var showCustomNameAlert = false
    @State private var pendingCustomName: String = ""
    @State private var showBlockedAlert = false
    @State private var blockedReason: String = ""
    private let canonicalPlaces: [CanonicalPlace] = CanonicalPlace.load()

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
            if !searchText.isEmpty {
                // Search Results
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Results")
                        .font(FontManager.primaryText())
                        .fontWeight(.semibold)
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 32)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Only show custom option if there are no results at all
                            if searchResults.count <= 2 {
                                UseTypedAsCustomRow(title: searchText) {
                                    let loc = LocationData(
                                        coordinate: region.center,
                                        placeName: searchText,
                                        address: nil,
                                        isCustomName: true
                                    )
                                    self.selectedLocation = loc
                                    self.showingMap = true
                                }
                            }
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
                            Button("Set custom name") {
                                promptCustomName()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(.caption)
                            .foregroundColor(Constants.Colors.primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 8) {
                            Button("Adjust Pin") {
                                showingMap = true
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Constants.Colors.primary)

                            Button("Change") {
                                selectedLocation = nil
                            }
                            .buttonStyle(PlainButtonStyle())
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
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
        .alert("Set custom location name", isPresented: $showCustomNameAlert) {
            TextField("e.g. Utopia of the Seas", text: $pendingCustomName)
            Button("Save") { applyCustomName() }
            Button("Cancel", role: .cancel) { pendingCustomName = "" }
        } message: {
            Text("This will be shown instead of the city/state.")
        }
        .alert("Name not allowed", isPresented: $showBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockedReason)
        }
    }

    private func setupLocationManager() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func loadNearbyPlaces() {
        SpotLogger.log(LocationSelectionViewLogs.loadingNearbyPlaces)
        guard let location = locationManager.location else {
            SpotLogger.log(LocationSelectionViewLogs.noCurrentLocationAvailable)
            // If no location, use default region
            searchNearbyPlaces(in: region)
            return
        }

        SpotLogger.log(LocationSelectionViewLogs.gotCurrentLocation, details: ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude])
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
                    SpotLogger.log(LocationSelectionViewLogs.nearbyPlaceSearchFailed, details: ["error": error.localizedDescription])
                } else if let response = response {
                    SpotLogger.log(LocationSelectionViewLogs.foundNearbyPlaces, details: ["count": response.mapItems.count])
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

        SpotLogger.log(LocationSelectionViewLogs.searchingPlaces, details: ["query": query])

        func runSearch(with span: MKCoordinateSpan, completion: @escaping ([MKMapItem]) -> Void) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let wideRegion = MKCoordinateRegion(center: region.center, span: span)
            request.region = wideRegion
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error = error {
                    SpotLogger.log(LocationSelectionViewLogs.searchPlacesFailed, details: ["error": error.localizedDescription])
                    completion([])
                } else {
                    completion(response?.mapItems ?? [])
                }
            }
        }

        // First: local region; Fallback: global span
        runSearch(with: region.span) { first in
            DispatchQueue.main.async {
                if !first.isEmpty {
                    SpotLogger.log(LocationSelectionViewLogs.foundLocalSearchResults, details: ["count": first.count, "query": query])
                    self.searchResults = first
                } else {
                    SpotLogger.log(LocationSelectionViewLogs.noLocalResultsRetryingGlobal)
                    runSearch(with: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)) { global in
                        DispatchQueue.main.async {
                            SpotLogger.log(LocationSelectionViewLogs.foundGlobalSearchResults, details: ["count": global.count, "query": query])
                            self.searchResults = global
                        }
                    }
                }
            }
        }
    }

    private func promptCustomName() {
        pendingCustomName = selectedLocation?.placeName ?? ""
        showCustomNameAlert = true
    }

    private func applyCustomName() {
        let name = pendingCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var current = selectedLocation else { return }
        // Validate with BlockedTerms
        let validator = PlaceNameValidator()
        switch validator.validate(name) {
        case .ok:
            break
        case .tooShort:
            blockedReason = "Please use at least 3 characters."
            showBlockedAlert = true
            pendingCustomName = ""
            showCustomNameAlert = false
            return
        case .tooLong:
            blockedReason = "Please keep it shorter."
            showBlockedAlert = true
            pendingCustomName = ""
            showCustomNameAlert = false
            return
        case .blocked:
            blockedReason = "That name isn’t allowed."
            showBlockedAlert = true
            pendingCustomName = ""
            showCustomNameAlert = false
            return
        }
        current = LocationData(
            coordinate: current.coordinate,
            placeName: name,
            address: current.address,
            isCustomName: true
        )
        selectedLocation = current
        pendingCustomName = ""
        showCustomNameAlert = false
    }
}

// MARK: - Canonical places support
struct CanonicalPlace: Decodable {
    let name: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let address: String?

    func matches(_ q: String) -> Bool {
        let s = q.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased() == s { return true }
        return aliases.contains(s)
    }

    static func load() -> [CanonicalPlace] {
        guard let url = Bundle.main.url(forResource: "CanonicalPlaces", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let places = try? JSONDecoder().decode([CanonicalPlace].self, from: data) else {
            return []
        }
        return places
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
                address: parts.isEmpty ? nil : parts,
                isCustomName: false
            )
            SpotLogger.log(LocationSelectionViewLogs.userSelectedLocation, details: ["placeName": locationData.placeName])
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
                address: parts.isEmpty ? nil : parts,
                isCustomName: false
            )
            SpotLogger.log(LocationSelectionViewLogs.userSelectedLocation, details: ["placeName": locationData.placeName])
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
    private let geocodeDebouncer = Debouncer(interval: 0.5)
    @State private var showAccuracyCircle = true
    @State private var accuracyRadius: CLLocationDistance = 50
    @State private var markerScale: CGFloat = 1.0
    @State private var initialLocation: LocationData
    @State private var hasUserMoved = false
    @State private var currentZoomLevel: Double = 0.01

    init(location: LocationData, onConfirm: @escaping (LocationData) -> Void) {
        self.location = location
        self.onConfirm = onConfirm
        let optimalSpan = Self.calculateOptimalSpan(for: location)
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: optimalSpan
        )
        _position = State(initialValue: .region(region))
        _draggedLocation = State(initialValue: location)
        _currentLocationName = State(initialValue: location.placeName)
        _initialLocation = State(initialValue: location)
        _currentZoomLevel = State(initialValue: optimalSpan.latitudeDelta)
        _accuracyRadius = State(initialValue: Self.calculateAccuracyRadius(for: optimalSpan.latitudeDelta))
    }
    
    private static func calculateOptimalSpan(for location: LocationData) -> MKCoordinateSpan {
        if location.isCustomName {
            return MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        } else if location.address?.contains(",") == true {
            return MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        } else {
            return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        }
    }
    
    private static func calculateAccuracyRadius(for latitudeDelta: Double) -> CLLocationDistance {
        return max(25, min(100, latitudeDelta * 5000))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    // Blue dot (appears when permission granted)
                    UserAnnotation()
                    
                    // Accuracy circle overlay
                    if showAccuracyCircle {
                        MapCircle(center: draggedLocation.coordinate, radius: accuracyRadius)
                            .foregroundStyle(Constants.Colors.primary.opacity(0.15))
                            .stroke(Constants.Colors.primary.opacity(0.3), lineWidth: 2)
                    }
                }
                // Debounced center updates while the map moves continuously
                .onMapCameraChange(frequency: .continuous) { context in
                    let center = context.region.center
                    hasUserMoved = true
                    currentZoomLevel = context.region.span.latitudeDelta
                    accuracyRadius = Self.calculateAccuracyRadius(for: currentZoomLevel)
                    
                    // Animate marker on drag
                    withAnimation(.easeOut(duration: 0.1)) {
                        markerScale = 0.9
                    }
                    
                    // Move selection immediately (for UI), then reverse-geocode after debounce
                    draggedLocation = LocationData(
                        coordinate: center,
                        placeName: draggedLocation.placeName,
                        address: draggedLocation.address,
                        isCustomName: draggedLocation.isCustomName
                    )
                    geocodeDebouncer.schedule { 
                        self.updateDraggedLocation(to: center)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            markerScale = 1.0
                        }
                    }
                }
                .preferredColorScheme(.light)
                // Center marker overlay (keeps marker fixed; map moves under it)
                .overlay(alignment: .center) {
                    ZStack {
                        // Shadow for depth
                        Circle()
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .offset(y: 20)
                            .blur(radius: 4)
                        
                        // Pin marker
                        Image("green_marker")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .scaleEffect(markerScale)
                            .offset(y: -20)
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .allowsHitTesting(false)
                }

                // Top “current name” chip
                VStack {
                    HStack(spacing: 8) {
                        if isGeocoding {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Constants.Colors.primary)
                        } else {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(Constants.Colors.primary)
                        }
                        Text(currentLocationName)
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                            .lineLimit(1)
                        Spacer()
                        
                        if hasUserMoved {
                            Button(action: resetToInitial) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 12))
                                    Text("Reset")
                                        .font(.caption.weight(.medium))
                                }
                                .foregroundColor(Constants.Colors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Zoom level indicator
                    HStack(spacing: 6) {
                        Image(systemName: "circle.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Constants.Colors.primary.opacity(0.7))
                        Text(precisionText)
                            .font(.caption2)
                            .foregroundColor(Constants.Colors.primary.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(8)
                    .padding(.top, 8)

                    Spacer()

                    // Confirm button with haptic feedback
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        Task { await confirmWithUpsert() }
                    }) {
                        HStack {
                            if isGeocoding {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(isGeocoding ? "Locating..." : "Confirm Location")
                                .font(FontManager.buttonText())
                                .foregroundColor(Constants.Colors.buttonText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.primary)
                        .cornerRadius(20)
                        .shadow(color: Constants.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)

                }
                // Map controls
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        MapUserLocationButton()
                        MapCompass()
                        
                        Button(action: {
                            withAnimation {
                                showAccuracyCircle.toggle()
                            }
                        }) {
                            Image(systemName: showAccuracyCircle ? "circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(Constants.Colors.primary)
                                .frame(width: 40, height: 40)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
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
            .onAppear {
                // Ensure keyboard is dismissed to avoid input accessory constraint noise
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    // MARK: - Reverse geocode the new center (debounced)
    private func updateDraggedLocation(to newCenter: CLLocationCoordinate2D) {
        geocodeWorkItem?.cancel()
        geocoder.cancelGeocode()
        isGeocoding = true
        
        let loc = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                defer { self.isGeocoding = false }
                if let ns = error as NSError? {
                    if ns.code != CLError.Code.network.rawValue && 
                       ns.code != CLError.Code.geocodeFoundNoResult.rawValue &&
                       ns.code != CLError.Code.geocodeCanceled.rawValue {
                        SpotLogger.log(LocationSelectionViewLogs.reverseGeocodeFailed, details: ["error": ns.localizedDescription])
                    }
                    return
                }
                guard let placemark = placemarks?.first else { return }
                let name = placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let city = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
                let state = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
                let country = placemark.country?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cityState = [city, state].compactMap { $0 }.joined(separator: ", ")
                let address = [city, state, country].compactMap { $0 }.joined(separator: ", ")
                let prettyName = (name?.isEmpty == false ? name! : (cityState.isEmpty ? self.draggedLocation.placeName : cityState))
                
                self.draggedLocation = LocationData(
                    coordinate: newCenter,
                    placeName: self.draggedLocation.isCustomName ? self.draggedLocation.placeName : prettyName,
                    address: address.isEmpty ? nil : address,
                    isCustomName: self.draggedLocation.isCustomName
                )
                self.currentLocationName = self.draggedLocation.isCustomName ? self.draggedLocation.placeName : prettyName
            }
        }
    }

    // MARK: - Upsert custom place before returning
    private func confirmWithUpsert() async {
        let selected = draggedLocation
        if selected.isCustomName {
            let validator = PlaceNameValidator()
            switch validator.validate(selected.placeName) {
            case .ok:
                break
            case .tooShort, .tooLong, .blocked:
                SpotLogger.log(LocationSelectionViewLogs.blockedCustomPlaceSkipUpsert)
            }
        }
        onConfirm(selected)
    }
    
    // MARK: - Reset to initial location
    private func resetToInitial() {
        withAnimation {
            let region = MKCoordinateRegion(
                center: initialLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: currentZoomLevel, longitudeDelta: currentZoomLevel)
            )
            position = .region(region)
            draggedLocation = initialLocation
            currentLocationName = initialLocation.placeName
            hasUserMoved = false
        }
        
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    // MARK: - Precision text based on zoom level
    private var precisionText: String {
        if currentZoomLevel < 0.002 {
            return "Very Precise (~25m)"
        } else if currentZoomLevel < 0.005 {
            return "Precise (~50m)"
        } else if currentZoomLevel < 0.01 {
            return "Accurate (~100m)"
        } else if currentZoomLevel < 0.02 {
            return "General Area (~200m)"
        } else {
            return "Broad Area (~500m+)"
        }
    }
}

// MARK: - Use typed text as custom place row
struct UseTypedAsCustomRow: View {
    let title: String
    let onUse: () -> Void
    var body: some View {
        Button(action: onUse) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Constants.Colors.primary)
                Text("Use ‘\(title)’ as a custom place")
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.primary)
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

#Preview {
    LocationSelectionView(selectedLocation: .constant(nil))
}
