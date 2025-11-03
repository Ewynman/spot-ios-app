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
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var toastIsError = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Images (optional replacement)
                PhotoSelectionView(selectedImages: $selectedImages)
                    .environmentObject(authVM)

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
                VibeSelectionView(selectedVibe: $selectedVibe)
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
        // Do not auto-download images; user can replace if they want.
    }

    private func presentMap() {
        // Present the existing map sheet used in post flow
        // We’ll emulate by toggling a sheet via Notification to keep code light.
        // For now, reuse by pushing a temporary sheet
        let loc = selectedLocation ?? LocationData(
            coordinate: CLLocationCoordinate2D(latitude: spot.latitude ?? 0, longitude: spot.longitude ?? 0),
            placeName: spot.locationName ?? "",
            address: nil,
            isCustomName: false
        )
        // Inline sheet
        let host = UIHostingController(rootView: LocationMapView(location: loc, onConfirm: { newLoc in
            self.selectedLocation = newLoc
        }))
        host.modalPresentationStyle = .formSheet
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.present(host, animated: true)
    }

    private func save() {
        guard !isSaving else { return }
        guard let loc = selectedLocation, !selectedVibe.isEmpty, let spotId = spot.id else {
            errorMessage = "Please select location and vibe"; toastIsError = true; withAnimation { showToast = true }; return
        }
        isSaving = true
        Task {
            do {
                if selectedImages.isEmpty {
                    try await SpotUploader.shared.updateSpot(
                        spotId: spotId,
                        images: nil,
                        vibeTag: selectedVibe,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        placeName: loc.placeName
                    )
                } else {
                    try await SpotUploader.shared.updateSpot(
                        spotId: spotId,
                        images: selectedImages,
                        vibeTag: selectedVibe,
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude,
                        placeName: loc.placeName
                    )
                }
                var updated = spot
                updated.vibeTag = selectedVibe
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
}
