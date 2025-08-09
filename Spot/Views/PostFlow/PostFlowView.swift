import SwiftUI
import FirebaseAuth
import CoreLocation

struct PostFlowView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 1
    @State private var selectedImage: UIImage?
    @State private var selectedLocation: LocationData?
    @State private var selectedVibe: String = ""
    @State private var isUploading = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIsError = false
    
    var onPostSuccess: (() -> Void)? = nil
    
    private let totalSteps = 3
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Progress Indicator
                    ProgressIndicatorView(currentStep: currentStep, totalSteps: totalSteps)
                    
                    // Step Content
                    Group {
                        switch currentStep {
                        case 1:
                            PhotoSelectionView(selectedImage: $selectedImage)
                        case 2:
                            LocationSelectionView(selectedLocation: $selectedLocation)
                        case 3:
                            VibeSelectionView(selectedVibe: $selectedVibe)
                        default:
                            EmptyView()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                    
                    // Navigation Buttons
                    NavigationButtonsView(
                        currentStep: $currentStep,
                        totalSteps: totalSteps,
                        canProceed: canProceedToNextStep,
                        onBack: handleBack,
                        onNext: handleNext,
                        onFinish: handleFinish
                    )
                }
                .background(Color(hex: "F5F3EF"))
                
                // Top status overlays
                VStack(spacing: 8) {
                    if isUploading {
                        ProgressBarView()
                            .transition(.move(edge: .top))
                    }
                    if showToast {
                        ToastView(message: toastMessage, isError: toastIsError)
                            .transition(.move(edge: .top))
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CustomBackButton {
                    dismiss()
                }
            }
        }
    }
    
    private var canProceedToNextStep: Bool {
        switch currentStep {
        case 1:
            return selectedImage != nil
        case 2:
            return selectedLocation != nil
        case 3:
            return !selectedVibe.isEmpty
        default:
            return false
        }
    }
    
    private func handleBack() {
        if currentStep > 1 {
            SpotLogger.debug("User went back from step \(currentStep) to step \(currentStep - 1)")
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep -= 1
            }
        }
    }
    
    private func handleNext() {
        if currentStep < totalSteps {
            SpotLogger.debug("User progressed from step \(currentStep) to step \(currentStep + 1)")
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        }
    }
    
    private func handleFinish() {
        SpotLogger.info("User completed post flow")
        SpotLogger.debug("Post data - Image: \(selectedImage != nil), Location: \(selectedLocation?.placeName ?? "None"), Vibe: \(selectedVibe)")
        
        guard let image = selectedImage,
              let location = selectedLocation,
              !selectedVibe.isEmpty,
              !location.placeName.isEmpty,
              location.coordinate.latitude != 0,
              location.coordinate.longitude != 0
        else {
            showToastWith(message: "All fields are required to post a spot.", isError: true)
            return
        }
        
        isUploading = true
        
        SpotUploader.shared.uploadSpot(
            image: image,
            vibeTag: selectedVibe,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            placeName: location.placeName
        ) { result in
            DispatchQueue.main.async {
                isUploading = false
                switch result {
                case .success:
                    if let userId = Auth.auth().currentUser?.uid {
                        SpotUploader.incrementUserVibeStat(userId: userId, vibeTag: selectedVibe)
                    }
                    showToastWith(message: "Spot posted!", isError: false)
                    SpotLogger.info("Spot posted and vibeStats updated")
                    onPostSuccess?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                case .failure(let error):
                    showToastWith(message: error.localizedDescription, isError: true)
                    SpotLogger.error("Spot upload failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showToastWith(message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showToast = false
            }
        }
    }
}

// MARK: - Progress Indicator
struct ProgressIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Constants.Colors.primary : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
}

// MARK: - Navigation Buttons
struct NavigationButtonsView: View {
    @Binding var currentStep: Int
    let totalSteps: Int
    let canProceed: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            if currentStep > 1 {
                Button(action: onBack) {
                    Text("Back")
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Constants.Colors.primary, lineWidth: 1)
                        )
                }
            }
            
            Button(action: currentStep == totalSteps ? onFinish : onNext) {
                Text(currentStep == totalSteps ? "Post" : "Next")
                    .font(FontManager.buttonText())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Constants.Colors.primary : Color.gray)
                    .cornerRadius(20)
            }
            .disabled(!canProceed)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Location Data Model
struct LocationData: Identifiable, Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let placeName: String
    let address: String?
    
    static func == (lhs: LocationData, rhs: LocationData) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Progress Bar View
struct ProgressBarView: View {
    @State private var progress: CGFloat = 0.0
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                Capsule()
                    .fill(Constants.Colors.primary)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: progress)
            }
            .onAppear {
                progress = 0.7
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    progress = 1.0
                }
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 0)
    }
}

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let isError: Bool
    var body: some View {
        Text(message)
            .font(FontManager.primaryText())
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(isError ? Color.red : Constants.Colors.primary)
            .cornerRadius(20)
            .shadow(radius: 4)
    }
}

#Preview {
    PostFlowView()
}
 
