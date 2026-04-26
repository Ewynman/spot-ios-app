import SwiftUI
import MapKit
import CoreLocation

struct EditSpotView: View {
    let spot: Spot
    var onSaved: ((Spot) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    // Form state
    @State private var selectedImages: [UIImage] = []
    @State private var selectedLocation: LocationData?
    @State private var selectedVibe: String = ""
    @State private var selectedVibes: [String] = []
    @State private var showingMap = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var toastIsError = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Images (optional replacement)
                PhotoSelectionView(selectedImages: $selectedImages, draftCount: 0, onOpenDrafts: {})
                    .environmentObject(authVM)

                if existingImageURLs.isEmpty == false {
                    existingImagesSection
                }

                // Location
                VStack(spacing: 8) {
                    HStack {
                        Text("Location")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    if let loc = selectedLocation {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundColor(Constants.Colors.primary)
                            Text(loc.placeName).font(FontManager.primaryText()).foregroundColor(Constants.Colors.primary)
                            Spacer()
                            Button("Change") { presentMap() }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                        .padding(.horizontal, 16)
                    } else {
                        Button(action: presentMap) {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle")
                                Text("Select location")
                                    .font(FontManager.primaryText())
                            }
                            .foregroundColor(Constants.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Vibe
                VibeSelectionView(selectedVibes: $selectedVibes, maxVibes: selectedImages.count > 1 ? 5 : 3)
                    .environmentObject(authVM)

                Spacer()

                Button(action: save) {
                    Text(isSaving ? "Saving..." : "Save Changes")
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.primary)
                        .cornerRadius(20)
                        .padding(.horizontal, 16)
                }
                .disabled(isSaving)
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 12)
            }
            .navigationTitle("Edit Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(PlainButtonStyle())
                }
            }
            .onAppear { seedFromSpot() }
            .sheet(isPresented: $showingMap) {
                if let loc = mapSeedLocation {
                    LocationMapView(location: loc) { newLoc in
                        selectedLocation = newLoc
                        showingMap = false
                    }
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if showToast, let msg = errorMessage {
                        ToastView(message: msg, isError: toastIsError)
                            .transition(.move(edge: .top))
                    }
                    if showSuccess {
                        SuccessToastView(message: "Saved")
                            .transition(.move(edge: .top))
                    }
                }
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.light)
        .background(Constants.Colors.background.ignoresSafeArea())
    }

    private func seedFromSpot() {
        // Location
        if let lat = spot.latitude, let lon = spot.longitude {
            selectedLocation = LocationData(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                placeName: spot.locationName ?? "",
                address: nil,
                isCustomName: false
            )
        }
        // Vibe
        selectedVibe = spot.vibeTag ?? ""
        selectedVibes = spot.displayVibeTags
    }

    private var existingImageURLs: [String] {
        if let urls = spot.imageURLs, !urls.isEmpty {
            return urls
        }
        if let single = spot.imageURL, !single.isEmpty {
            return [single]
        }
        return []
    }

    private var mapSeedLocation: LocationData? {
        if let selectedLocation {
            return selectedLocation
        }
        guard spot.latitude != nil, spot.longitude != nil else {
            return nil
        }
        return LocationData(
            coordinate: CLLocationCoordinate2D(latitude: spot.latitude ?? 0, longitude: spot.longitude ?? 0),
            placeName: spot.locationName ?? "",
            address: nil,
            isCustomName: false
        )
    }

    private func presentMap() {
        showingMap = true
    }

    private func save() {
        guard !isSaving else { return }
        let primaryVibe = selectedVibes.first ?? selectedVibe
        guard let loc = selectedLocation, !primaryVibe.isEmpty, let spotId = spot.id else {
            errorMessage = "Please select location and vibe"; toastIsError = true; withAnimation { showToast = true }; return
        }
        isSaving = true
        Task {
            do {
                guard let sid = UUID(uuidString: spotId) else {
                    throw NSError(domain: "EditSpotView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid spot id"])
                }
                if !selectedImages.isEmpty {
                    throw NSError(domain: "EditSpotView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Image replacement in edit flow is temporarily unavailable."])
                }
                try await SpotSupabaseRepository.updateSpotMetadata(
                    id: sid,
                    vibeTags: selectedVibes.isEmpty ? [primaryVibe] : selectedVibes,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    locationName: loc.placeName
                )
                var updated = spot
                updated.vibeTag = primaryVibe
                updated.vibeTags = selectedVibes.isEmpty ? [primaryVibe] : selectedVibes
                updated.latitude = loc.coordinate.latitude
                updated.longitude = loc.coordinate.longitude
                updated.locationName = loc.placeName
                await MainActor.run {
                    onSaved?(updated)
                    isSaving = false
                    showSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { showSuccess = false }
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    toastIsError = true
                    withAnimation { showToast = true }
                }
            }
        }
    }

    private var existingImagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Images")
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(existingImageURLs, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Image("image_placeholder").resizable().scaledToFill()
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

#Preview {
    let sample = Spot(
        id: "s1",
        userId: "u1",
        username: "eddie",
        imageURL: "https://picsum.photos/seed/spot1/800/600",
        vibeTag: "Chill",
        latitude: 34.0522,
        longitude: -118.2437,
        locationName: "Los Angeles, CA",
        createdAt: Date()
    )
    let auth = AuthViewModel()
    auth.isPro = true
    return EditSpotView(spot: sample) { _ in }
        .environmentObject(auth)
}
