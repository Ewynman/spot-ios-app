import SwiftUI
import PhotosUI

struct PhotoSelectionView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedImages: [UIImage]
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Select Your Spot")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                Text("Choose a photo to share your spot")
                    .font(FontManager.primaryText())
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Image grid (selected + placeholders)
            if true {
                VStack(spacing: 16) {
                    let maxCount = authVM.isPro ? 5 : 1
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        // Existing images with remove buttons
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 110)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Constants.Colors.primary, lineWidth: 1)
                                    )

                                Button {
                                    selectedImages.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6).clipShape(Circle()))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(6)

                                // Reorder controls
                                HStack(spacing: 8) {
                                    if idx > 0 {
                                        Button { moveImage(from: idx, to: idx - 1) } label: {
                                            Image(systemName: "chevron.left.circle.fill").foregroundColor(.white)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    if idx < selectedImages.count - 1 {
                                        Button { moveImage(from: idx, to: idx + 1) } label: {
                                            Image(systemName: "chevron.right.circle.fill").foregroundColor(.white)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.top, 6)
                                .padding(.trailing, 38)
                            }
                        }

                        // Placeholder tiles
                        let remaining = max(0, maxCount - selectedImages.count)
                        if remaining > 0 {
                            if authVM.isPro {
                                // Pro: all placeholders are "+" gallery tiles (no camera tile in grid)
                                ForEach(0..<remaining, id: \.self) { _ in
                                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: remaining, matching: .images) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                                .foregroundColor(Constants.Colors.primary)
                                                .frame(height: 110)
                                            Image(systemName: "plus")
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundColor(Constants.Colors.primary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                // Free: show camera tile + single-select "+" tiles
                                Button { showCamera = true } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                            .foregroundColor(Constants.Colors.primary)
                                            .frame(height: 110)
                                        Image(systemName: "camera")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(Constants.Colors.primary)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())

                                let gallerySlots = max(0, remaining - 1)
                                ForEach(0..<gallerySlots, id: \.self) { _ in
                                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 1, matching: .images) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                                .foregroundColor(Constants.Colors.primary)
                                                .frame(height: 110)
                                            Image(systemName: "plus")
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundColor(Constants.Colors.primary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)

                    if !selectedImages.isEmpty {
                        Button("Clear Photos") { selectedImages.removeAll() }
                            .buttonStyle(PlainButtonStyle())
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
            }

            // Additional actions
            VStack(spacing: 20) {
                // Gallery button for first add when grid is empty or for additional adds
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: max(1, (authVM.isPro ? 5 : 1) - selectedImages.count), matching: .images) {
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
                Button(action: { showCamera = true }) {
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
            .padding(.horizontal, 32)

            Spacer()
        }
        .task(id: photoPickerItems) {
            guard !photoPickerItems.isEmpty else { return }
            var newImages: [UIImage] = []
            let maxCount = authVM.isPro ? 5 : 1
            for item in photoPickerItems.prefix(maxCount) {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    newImages.append(uiImage)
                }
            }
            if !newImages.isEmpty {
                SpotLogger.info("User selected \(newImages.count) photo(s) from gallery")
                // Append up to the max allowed count
                let available = max(0, (authVM.isPro ? 5 : 1) - selectedImages.count)
                if available > 0 {
                    selectedImages.append(contentsOf: newImages.prefix(available))
                }
            } else {
                SpotLogger.warning("Failed to load selected photos from gallery")
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(selectedImages: $selectedImages, maxCount: authVM.isPro ? 5 : 1)
        }
    }
}

// MARK: - Helpers
private extension PhotoSelectionView {
    func moveImage(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, from < selectedImages.count, to < selectedImages.count else { return }
        let img = selectedImages.remove(at: from)
        selectedImages.insert(img, at: to)
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
                SpotLogger.info("User captured photo with camera")
                var imgs = parent.selectedImages
                if parent.maxCount <= 1 {
                    imgs = [image]
                } else {
                    if imgs.count < parent.maxCount { imgs.append(image) } else { imgs[parent.maxCount - 1] = image }
                }
                parent.selectedImages = imgs
            } else {
                SpotLogger.warning("Failed to capture photo with camera")
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            SpotLogger.debug("User cancelled camera capture")
            parent.dismiss()
        }
    }
}
