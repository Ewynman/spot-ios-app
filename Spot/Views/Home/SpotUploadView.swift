//
//  SpotUploadView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import PhotosUI

struct SpotUploadView: View {
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var caption: String = ""
    @State private var vibeTag: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadMessage: String?

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
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#2D4A3D"), lineWidth: 1)
                        )

                    // Vibe tag
                    TextField("Enter a vibe tag...", text: $vibeTag)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#2D4A3D"), lineWidth: 1)
                        )

                    // Upload Button
                    Button(action: uploadSpot) {
                        Text(isUploading ? "Uploading..." : "Post Spot")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: "#3F7F5F"))
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
            .navigationTitle("Upload Spot")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func uploadSpot() {
        guard let image = selectedImage else { return }

        isUploading = true
        uploadMessage = nil

        SpotUploader.shared.uploadSpot(image: image, caption: caption, vibeTag: vibeTag) { result in
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

#Preview {
    SpotUploadView()
}
