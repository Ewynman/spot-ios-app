import SwiftUI
import CoreLocation

struct PostFlowView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 1
    @State private var selectedImage: UIImage?
    @State private var selectedLocation: LocationData?
    @State private var selectedVibe: String = ""
    
    private let totalSteps = 3
    
    var body: some View {
        NavigationStack {
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
        
        // TODO: Upload the post
        print("Posting with:")
        print("- Image: \(selectedImage != nil)")
        print("- Location: \(selectedLocation?.placeName ?? "None")")
        print("- Vibe: \(selectedVibe)")
        
        dismiss()
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

#Preview {
    PostFlowView()
}
