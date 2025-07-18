import SwiftUI
import PhotosUI

struct PhotoSelectionView: View {
    @Binding var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
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
            
            // Image Preview or Selection Options
            if let image = selectedImage {
                VStack(spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Constants.Colors.primary, lineWidth: 2)
                        )
                    
                    Button("Change Photo") {
                        selectedImage = nil
                    }
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.primary)
                }
            } else {
                // Photo Selection Options
                VStack(spacing: 20) {
                    // Gallery Picker
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
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
                    Button(action: {
                        showCamera = true
                    }) {
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
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .onChange(of: photoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(selectedImage: $selectedImage)
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
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
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    PhotoSelectionView(selectedImage: .constant(nil))
} 