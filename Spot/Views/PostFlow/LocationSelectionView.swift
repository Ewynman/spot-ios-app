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
    @State private var searchFieldFocused = false
    private let canonicalPlaces: [CanonicalPlace] = CanonicalPlace.load()

    private let locationManager = CLLocationManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header with search integrated
            VStack(spacing: 16) {
                Text("Where's your Spot?")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)
                    .padding(.top, 24)

                // Enhanced Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(searchFieldFocused ? Constants.Colors.primary : .gray)
                    
                    TextField("Search places...", text: $searchText)
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                        .onChange(of: searchText) { _, newValue in
                            searchPlaces(query: newValue)
                        }
                        .onSubmit {
                            searchFieldFocused = false
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Constants.Colors.accent.opacity(0.3))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(searchFieldFocused ? Constants.Colors.primary : Color.clear, lineWidth: 2)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(Constants.Colors.background)

            // Content based on search with improved UI
            ScrollView {
                VStack(spacing: 0) {
                    if !searchText.isEmpty {
                        // Search Results Section
                        if isSearching {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Searching...")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .frame(height: 120)
                        } else if searchResults.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(.top, 40)
                                
                                Text("No places found")
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.gray)
                                
                                // Custom place option
                                Button(action: {
                                    let loc = LocationData(
                                        coordinate: region.center,
                                        placeName: searchText,
                                        address: nil,
                                        isCustomName: true
                                    )
                                    self.selectedLocation = loc
                                    self.showingMap = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Use '\(searchText)' as custom place")
                                            .fontWeight(.medium)
                                    }
                                    .font(FontManager.primaryText())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Constants.Colors.primary)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.bottom, 20)
                            }
                        } else {
                            VStack(spacing: 2) {
                                // Section header
                                HStack {
                                    Text("Results")
                                        .font(FontManager.primaryText())
                                        .fontWeight(.semibold)
                                        .foregroundColor(Constants.Colors.primary)
                                    Spacer()
                                    Text("\(searchResults.count)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Constants.Colors.background)
                                
                                ForEach(searchResults, id: \.self) { item in
                                    ImprovedLocationRow(item: item) { location in
                                        selectedLocation = location
                                        showingMap = true
                                    }
                                    Divider()
                                        .padding(.leading, 60)
                                }
                                
                                // Custom place option at bottom of results
                                if searchResults.count > 0 && searchResults.count < 5 {
                                    Button(action: {
                                        let loc = LocationData(
                                            coordinate: region.center,
                                            placeName: searchText,
                                            address: nil,
                                            isCustomName: true
                                        )
                                        self.selectedLocation = loc
                                        self.showingMap = true
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(Constants.Colors.primary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Use '\(searchText)' as custom place")
                                                    .font(FontManager.primaryText())
                                                    .foregroundColor(Constants.Colors.primary)
                                                Text("For unique or moving locations")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(Constants.Colors.accent.opacity(0.2))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    } else {
                        // Nearby Places Section
                        VStack(spacing: 2) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(Constants.Colors.primary)
                                Text("Nearby Places")
                                    .font(FontManager.primaryText())
                                    .fontWeight(.semibold)
                                    .foregroundColor(Constants.Colors.primary)
                                Spacer()
                                if !isLoadingNearby {
                                    Text("\(nearbyPlaces.count)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Constants.Colors.background)
                            
                            if isLoadingNearby {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 12) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                        Text("Finding nearby places...")
                                            .font(FontManager.primaryText())
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .frame(height: 120)
                            } else if nearbyPlaces.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "map")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .padding(.top, 40)
                                    Text("No nearby places found")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(.gray)
                                    Text("Try searching for a specific place")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.bottom, 40)
                                }
                            } else {
                                ForEach(nearbyPlaces, id: \.self) { item in
                                    ImprovedLocationRow(item: item) { location in
                                        selectedLocation = location
                                        showingMap = true
                                    }
                                    if item != nearbyPlaces.last {
                                        Divider()
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Selected Location Preview Card
            if let location = selectedLocation {
                VStack(spacing: 0) {
                    Divider()
                    
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.placeName)
                                    .font(FontManager.primaryText())
                                    .fontWeight(.semibold)
                                    .foregroundColor(Constants.Colors.primary)
                                    .lineLimit(1)

                                if let address = location.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                showingMap = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "map")
                                    Text("Adjust")
                                }
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Constants.Colors.accent.opacity(0.3))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                promptCustomName()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                    Text("Rename")
                                }
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Constants.Colors.accent.opacity(0.3))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                selectedLocation = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.gray)
                                    .frame(width: 44, height: 44)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(20)
                    .background(Constants.Colors.background)
                }
            }
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
            isSearching = false
            return
        }

        isSearching = true
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
                    self.isSearching = false
                } else {
                    SpotLogger.log(LocationSelectionViewLogs.noLocalResultsRetryingGlobal)
                    runSearch(with: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)) { global in
                        DispatchQueue.main.async {
                            SpotLogger.log(LocationSelectionViewLogs.foundGlobalSearchResults, details: ["count": global.count, "query": query])
                            self.searchResults = global
                            self.isSearching = false
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

// MARK: - Improved Location Row
struct ImprovedLocationRow: View {
    let item: MKMapItem
    let onSelect: (LocationData) -> Void
    
    private var distanceText: String? {
        guard let distance = item.placemark.location?.distance(from: CLLocation(latitude: 0, longitude: 0)) else {
            return nil
        }
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }

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
            
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            
            SpotLogger.log(LocationSelectionViewLogs.userSelectedLocation, details: ["placeName": locationData.placeName])
            onSelect(locationData)
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Constants.Colors.accent.opacity(0.4))
                        .frame(width: 44, height: 44)
                    
                    Image("green_marker")
                        .resizable()
                        .frame(width: 22, height: 22)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown Location")
                        .font(FontManager.primaryText())
                        .fontWeight(.medium)
                        .foregroundColor(Constants.Colors.primary)
                        .lineLimit(1)
                    
                    let city = item.placemark.locality
                    let state = item.placemark.administrativeArea
                    let country = item.placemark.country
                    let parts = [city, state, country].compactMap { $0 }.joined(separator: ", ")
                    if !parts.isEmpty {
                        Text(parts)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
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
    @State private var markerScale: CGFloat = 1.0
    @State private var initialLocation: LocationData
    @State private var hasUserMoved = false

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
    

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    // Blue dot (appears when permission granted)
                    UserAnnotation()
                }
                // Debounced center updates while the map moves continuously
                .onMapCameraChange(frequency: .continuous) { context in
                    let center = context.region.center
                    hasUserMoved = true
                    
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
        geocoder.reverseGeocodeLocation(loc) { placemarks, error in
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
            let optimalSpan = Self.calculateOptimalSpan(for: initialLocation)
            let region = MKCoordinateRegion(
                center: initialLocation.coordinate,
                span: optimalSpan
            )
            position = .region(region)
            draggedLocation = initialLocation
            currentLocationName = initialLocation.placeName
            hasUserMoved = false
        }
        
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
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
