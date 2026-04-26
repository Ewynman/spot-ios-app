import SwiftUI
import AVFoundation

struct CameraPermissionView: View {
    let authDestination: NotificationPermissionView.AuthDestination
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var navigateToSignup = false
    @State private var navigateToLogin = false
    @State private var navigateToPostAuthSetup = false

    var body: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    CustomBackButton { dismiss() }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("Allow").font(FontManager.sectionHeader()).foregroundColor(Constants.Colors.primary)
                    Text("Camera Access").font(FontManager.sectionHeader()).foregroundColor(Constants.Colors.primary)
                }
                Text("Spot needs camera access so you can capture new spots instantly.")
                    .font(FontManager.primaryText())
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.Colors.primary)

                Spacer()
                Image("waves").resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity).frame(height: 200)
                Spacer()

                VStack(spacing: 12) {
                    Button(permissionManager.cameraStatus == .notDetermined ? "Allow Camera" : "Open Settings") {
                        if permissionManager.cameraStatus == .notDetermined {
                            permissionManager.requestCameraPermission()
                        } else {
                            permissionManager.openCameraSettings()
                        }
                    }
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .frame(maxWidth: .infinity).padding()
                        .background(Constants.Colors.primary).cornerRadius(20)
                        .buttonStyle(PlainButtonStyle())
                    Button("Maybe Later") { routeToDestination() }
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.primary)
                        .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.top)
        }
        .navigationDestination(isPresented: $navigateToSignup) { SignupView() }
        .navigationDestination(isPresented: $navigateToLogin) { LoginView() }
        .navigationDestination(isPresented: $navigateToPostAuthSetup) { PostAuthSetupFlowView(onComplete: {}) }
        .onAppear {
            permissionManager.updatePermissionStatuses()
            if permissionManager.cameraStatus != .notDetermined {
                routeToDestination()
            }
        }
        .onChange(of: permissionManager.cameraStatus) { _, newStatus in
            if newStatus == .authorized {
                routeToDestination()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func routeToDestination() {
        switch authDestination {
        case .signup:
            navigateToSignup = true
        case .login:
            navigateToLogin = true
        case .postAuthSetup:
            navigateToPostAuthSetup = true
        }
    }
}
