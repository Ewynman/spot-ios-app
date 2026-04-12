import SwiftUI
import CoreLocation

struct PostFlowView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = PostFlowViewModel()
    @AppStorage("hasAcceptedPostingRules") private var hasAcceptedPostingRules: Bool = false
    @State private var showRulesSheet: Bool = false
    /// `true` while we await a fresh `isEmailVerified` value from Firebase so we
    /// never flash the "verification required" error on a stale cached token.
    @State private var isVerifyingEmail: Bool = true

    var onPostSuccess: ((Spot) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if isVerifyingEmail {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Constants.Colors.primary)
                        Spacer()
                    } else if !authVM.isEmailVerified {
                        VStack(spacing: 12) {
                            Text("Email verification required to post")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            Button(action: { dismiss() }) {
                                Text("Close")
                                    .font(FontManager.buttonText())
                                    .foregroundColor(Constants.Colors.buttonText)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Constants.Colors.primary)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(16)
                        .background(Constants.Colors.background)
                    } else {
                        ProgressIndicatorView(currentStep: viewModel.currentStep, totalSteps: viewModel.totalSteps)

                        Group {
                            switch viewModel.currentStep {
                            case 1:
                                PhotoSelectionView(selectedImages: $viewModel.selectedImages)
                            case 2:
                                LocationSelectionView(selectedLocation: $viewModel.selectedLocation)
                            case 3:
                                VibeSelectionView(selectedVibe: $viewModel.selectedVibe)
                            default:
                                EmptyView()
                            }
                        }
                        .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

                        NavigationButtonsView(
                            currentStep: $viewModel.currentStep,
                            totalSteps: viewModel.totalSteps,
                            canProceed: viewModel.canProceedToNextStep && !viewModel.isPosting,
                            isPosting: viewModel.isPosting,
                            onBack: { viewModel.goBack() },
                            onNext: { viewModel.goNext() },
                            onFinish: { viewModel.submitPost() }
                        )
                    }
                }

                VStack(spacing: 8) {
                    if viewModel.isUploading {
                        ProgressBarView()
                            .transition(.move(edge: .top))
                    }
                    if viewModel.showToast {
                        ToastView(message: viewModel.toastMessage, isError: viewModel.toastIsError)
                            .transition(.move(edge: .top))
                    }
                    if viewModel.showSuccessBanner {
                        SuccessToastView(message: "Spot posted!")
                            .transition(.move(edge: .top))
                    }
                }
                .padding(.top, 8)
            }
            .background(Constants.Colors.background.ignoresSafeArea())
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CustomBackButton {
                    dismiss()
                }
            }
        }
        .onAppear {
            viewModel.authViewModel = authVM
            viewModel.onPostSuccess = onPostSuccess
            viewModel.onShouldDismiss = { dismiss() }
            Task {
                _ = await authVM.checkVerificationStatus()
                isVerifyingEmail = false
                showRulesIfNeeded()
            }
        }
        .onChange(of: authVM.isEmailVerified) { _, newValue in
            if newValue { showRulesIfNeeded() }
        }
        .sheet(isPresented: $showRulesSheet) {
            PostingRulesView(onAgree: {
                hasAcceptedPostingRules = true
                showRulesSheet = false
            })
            .environmentObject(authVM)
        }
    }

    private func showRulesIfNeeded() {
        if authVM.isEmailVerified && !hasAcceptedPostingRules {
            showRulesSheet = true
        }
    }
}

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
    let isPosting: Bool
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
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: currentStep == totalSteps ? onFinish : onNext) {
                Text(currentStep == totalSteps ? (isPosting ? "Posting..." : "Post") : "Next")
                    .font(FontManager.buttonText())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed && !isPosting ? Constants.Colors.primary : Color.gray)
                    .cornerRadius(20)
            }
            .disabled(!canProceed || isPosting)
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
    let isCustomName: Bool

    init(coordinate: CLLocationCoordinate2D, placeName: String, address: String?, isCustomName: Bool = false) {
        self.coordinate = coordinate
        self.placeName = placeName
        self.address = address
        self.isCustomName = isCustomName
    }

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
        .environmentObject(AuthViewModel())
}
