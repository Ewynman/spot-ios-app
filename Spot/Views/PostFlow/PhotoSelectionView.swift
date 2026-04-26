import SwiftUI
import PhotosUI
import UIKit
import ImageIO

private let postImageMaxPixelSize: CGFloat = 1600

struct PhotoSelectionView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var permissionManager: PermissionManager
    @Binding var selectedImages: [UIImage]
    let draftCount: Int
    let onOpenDrafts: () -> Void
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var replacePickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoSettingsAlert = false
    @State private var showCameraSettingsAlert = false
    @State private var selectedPhotoIndex: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a Spot")
                        .font(FontManager.sectionHeader())
                        .foregroundColor(Constants.Colors.primary)
                    Text(selectedImages.isEmpty ? "Start with photos, or continue a saved draft." : "Review, reorder, replace, and add photos.")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
                Spacer()
                Button(action: onOpenDrafts) {
                    VStack(spacing: 2) {
                        Text("Drafts")
                            .font(.caption.weight(.semibold))
                        Text("\(draftCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(Constants.Colors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Constants.Colors.primary, lineWidth: 1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)

            if selectedImages.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 28))
                        .foregroundColor(Constants.Colors.primary)
                    Text("Add at least one photo to continue")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundColor(Constants.Colors.primary))
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .tag(idx)
                                .frame(maxWidth: .infinity)
                                .frame(height: 300)
                                .clipped()
                                .cornerRadius(16)
                                .padding(.horizontal, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 300)

                    HStack {
                        Text("\(selectedPhotoIndex + 1) of \(selectedImages.count)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        PhotosPicker(selection: $replacePickerItem, matching: .images) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Constants.Colors.primary)

                        Button {
                            deleteSelectedImage()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                                VStack(spacing: 6) {
                                    Button {
                                        selectedPhotoIndex = idx
                                    } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 62, height: 62)
                                            .clipped()
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(idx == selectedPhotoIndex ? Constants.Colors.primary : Color.clear, lineWidth: 2)
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    HStack(spacing: 4) {
                                        Button { moveImage(from: idx, to: idx - 1) } label: {
                                            Image(systemName: "arrow.left.circle")
                                        }
                                        .disabled(idx == 0)
                                        Button { moveImage(from: idx, to: idx + 1) } label: {
                                            Image(systemName: "arrow.right.circle")
                                        }
                                        .disabled(idx == selectedImages.count - 1)
                                    }
                                    .foregroundColor(Constants.Colors.primary)
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }

            // Additional actions
            VStack(spacing: 20) {
                // Gallery button for first add when grid is empty or for additional adds
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: max(1, maxPhotoCount - selectedImages.count), matching: .images) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(Constants.Colors.primary)

                        Text("Choose from Gallery")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Constants.Colors.primary, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(photoSelectionDisabled || selectedImages.count >= maxPhotoCount)

                if photoSelectionDisabled {
                    Button("Enable Photo Access in Settings") {
                        showPhotoSettingsAlert = true
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.primary)
                }

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)

                // Camera Button
                Button(action: { openCameraIfPermitted() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundColor(Constants.Colors.primary)

                        Text("Take a Photo")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Constants.Colors.primary, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear {
            permissionManager.updatePermissionStatuses()
        }
        .task(id: photoPickerItems) {
            guard !photoPickerItems.isEmpty else { return }
            var newImages: [UIImage] = []
            let maxCount = maxPhotoCount
            for item in photoPickerItems.prefix(maxCount) {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = downsampledPostImage(from: data, maxPixelSize: postImageMaxPixelSize) {
                    newImages.append(uiImage)
                }
            }
            photoPickerItems = []
            if !newImages.isEmpty {
                SpotLogger.log(PhotoSelectionViewLogs.photosSelectedFromGallery, details: ["count": newImages.count])
                // Append up to the max allowed count
                let available = max(0, maxPhotoCount - selectedImages.count)
                if available > 0 {
                    selectedImages.append(contentsOf: newImages.prefix(available))
                    selectedPhotoIndex = max(0, selectedImages.count - 1)
                }
            } else {
                SpotLogger.log(PhotoSelectionViewLogs.loadPhotosFailed)
            }
        }
        .task(id: replacePickerItem) {
            guard let replacePickerItem else { return }
            defer { self.replacePickerItem = nil }
            guard selectedPhotoIndex >= 0, selectedPhotoIndex < selectedImages.count else { return }
            if let data = try? await replacePickerItem.loadTransferable(type: Data.self),
               let uiImage = downsampledPostImage(from: data, maxPixelSize: postImageMaxPixelSize) {
                selectedImages[selectedPhotoIndex] = uiImage
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(selectedImages: $selectedImages, maxCount: maxPhotoCount)
        }
        .alert("Photo Access Needed", isPresented: $showPhotoSettingsAlert) {
            Button("Open Settings") { permissionManager.openPhotoSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow photo library access in Settings to choose from gallery.")
        }
        .alert("Camera Access Needed", isPresented: $showCameraSettingsAlert) {
            Button("Open Settings") { permissionManager.openCameraSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow camera access in Settings to take a photo.")
        }
    }
}

#Preview {
    StatefulImagesWrapper { binding in
        let auth = AuthViewModel()
        auth.isPro = true
        return PhotoSelectionView(selectedImages: binding, draftCount: 2, onOpenDrafts: {})
            .environmentObject(auth)
    }
}

private struct StatefulImagesWrapper<Content: View>: View {
    @State var images: [UIImage] = []
    let content: (Binding<[UIImage]>) -> Content
    var body: some View { content($images) }
}

// MARK: - Helpers
private extension PhotoSelectionView {
    var maxPhotoCount: Int { authVM.isPro ? 5 : 1 }

    var photoSelectionDisabled: Bool {
        permissionManager.photoStatus == .denied || permissionManager.photoStatus == .restricted
    }

    func moveImage(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, from < selectedImages.count, to < selectedImages.count else { return }
        let img = selectedImages.remove(at: from)
        selectedImages.insert(img, at: to)
        if selectedPhotoIndex == from {
            selectedPhotoIndex = to
        } else if from < selectedPhotoIndex && to >= selectedPhotoIndex {
            selectedPhotoIndex -= 1
        } else if from > selectedPhotoIndex && to <= selectedPhotoIndex {
            selectedPhotoIndex += 1
        }
    }

    func deleteSelectedImage() {
        guard selectedPhotoIndex >= 0, selectedPhotoIndex < selectedImages.count else { return }
        selectedImages.remove(at: selectedPhotoIndex)
        selectedPhotoIndex = max(0, min(selectedPhotoIndex, selectedImages.count - 1))
    }

    func openCameraIfPermitted() {
        permissionManager.updatePermissionStatuses()
        switch permissionManager.cameraStatus {
        case .authorized:
            showCamera = true
        case .notDetermined:
            permissionManager.requestCameraPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                permissionManager.updatePermissionStatuses()
                if permissionManager.cameraStatus == .authorized {
                    showCamera = true
                } else if permissionManager.cameraStatus == .denied || permissionManager.cameraStatus == .restricted {
                    showCameraSettingsAlert = true
                }
            }
        case .denied, .restricted:
            showCameraSettingsAlert = true
        @unknown default:
            showCameraSettingsAlert = true
        }
    }
}

private func downsampledPostImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let options: CFDictionary = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
    return UIImage(cgImage: cgImage)
}

private func resizedPostImage(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage? {
    let width = image.size.width
    let height = image.size.height
    let longestEdge = max(width, height)
    guard longestEdge > maxPixelSize else { return image }
    let ratio = maxPixelSize / longestEdge
    let target = CGSize(width: floor(width * ratio), height: floor(height * ratio))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: target, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let maxCount: Int
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                SpotLogger.log(PhotoSelectionViewLogs.photoCapturedWithCamera)
                let normalized = resizedPostImage(image, maxPixelSize: postImageMaxPixelSize) ?? image
                var imgs = parent.selectedImages
                if parent.maxCount <= 1 {
                    imgs = [normalized]
                } else {
                    if imgs.count < parent.maxCount { imgs.append(normalized) } else { imgs[parent.maxCount - 1] = normalized }
                }
                parent.selectedImages = imgs
            } else {
                SpotLogger.log(PhotoSelectionViewLogs.capturePhotoFailed)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            SpotLogger.log(PhotoSelectionViewLogs.cameraCancelled)
            parent.dismiss()
        }
    }
}
