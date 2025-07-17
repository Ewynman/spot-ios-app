//
//  SpotUploadView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import PhotosUI
import CoreLocation

struct SpotUploadView: View {
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var caption: String = ""
    @State private var vibeTag: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadMessage: String?
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Picker
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        ZStack {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 240)
                                    .clipped()
                                    .cornerRadius(16)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .frame(height: 240)
                                    .overlay(
                                        Text("Tap to select photo")
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                    }
                    .onChange(of: photoPickerItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                selectedImage = uiImage
                            }
                        }
                    }

                    // Caption
                    TextField("Enter a caption...", text: $caption)
                        .padding()
                        .background(Constants.Colors.background)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Constants.Colors.primary, lineWidth: 1)
                        )
                        .font(FontManager.primaryText())

                    // Vibe tag
                    TextField("Enter a vibe tag...", text: $vibeTag)
                        .padding()
                        .background(Constants.Colors.background)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Constants.Colors.accent, lineWidth: 1)
                        )
                        .font(FontManager.primaryText())

                    // Upload Button
                    Button(action: uploadSpot) {
                        Text(isUploading ? "Uploading..." : "Post Spot")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Constants.Colors.primary)
                            .cornerRadius(20)
                    }
                    .disabled(isUploading || selectedImage == nil)

                    // Message
                    if let message = uploadMessage {
                        Text(message)
                            .foregroundColor(.gray)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle(Text("Upload Spot").font(FontManager.sectionHeader()))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func uploadSpot() {
        guard let image = selectedImage else { return }

        isUploading = true
        uploadMessage = nil

        // Get current location
        let latitude = locationManager.location?.coordinate.latitude ?? 40.7128 // Default to NYC
        let longitude = locationManager.location?.coordinate.longitude ?? -74.0060
        SpotUploader.shared.uploadSpot(image: image, caption: caption, vibeTag: vibeTag, latitude: latitude, longitude: longitude) { result in
            DispatchQueue.main.async {
                isUploading = false
                switch result {
                case .success:
                    uploadMessage = "✅ Spot uploaded!"
                    caption = ""
                    vibeTag = ""
                    selectedImage = nil
                case .failure(let error):
                    uploadMessage = "❌ Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
    }
}

#Preview {
    SpotUploadView()
}
