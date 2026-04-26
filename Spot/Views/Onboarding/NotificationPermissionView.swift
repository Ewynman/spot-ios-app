//
//  NotificationPermissionView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct NotificationPermissionView: View {
    enum AuthDestination {
        case signup
        case login
        case postAuthSetup
    }

    let authDestination: AuthDestination
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var navigateToPhoto = false
    @State private var navigateToCamera = false
    @State private var navigateToSignup = false
    @State private var navigateToLogin = false
    @State private var navigateToPostAuthSetup = false

    init(authDestination: AuthDestination = .signup) {
        self.authDestination = authDestination
    }

    var body: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()

            VStack(spacing: 22) {

                    // Custom Back Button
                    HStack {
                        CustomBackButton {
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal)

                    // Title
                    VStack(spacing: 8) {
                        Text("Allow")
                            .font(FontManager.sectionHeader())
                            .foregroundColor(Constants.Colors.primary)

                        Text("Notification Access")
                            .font(FontManager.sectionHeader())
                            .foregroundColor(Constants.Colors.primary)
                    }

                    Text("Spot will let you know when new spots are nearby or when friends post something cool.")
                        .font(FontManager.primaryText())
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.Colors.primary)

                    Spacer()

                    // Waves Image
                    Image("waves")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .padding(.horizontal, 0)

                    Spacer()

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            if permissionManager.notificationStatus == .denied ||
                                permissionManager.notificationStatus == .provisional ||
                                permissionManager.notificationStatus == .ephemeral {
                                permissionManager.openNotificationSettings()
                            } else {
                                permissionManager.requestNotificationPermission()
                            }
                        }) {
                            Text(permissionManager.notificationStatus == .authorized ? "Notifications Enabled" : (permissionManager.notificationStatus == .notDetermined ? "Allow Notifications" : "Open Settings"))
                                .font(FontManager.buttonText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Constants.Colors.primary)
                                .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            goToAuthDestination()
                        }) {
                            Text("Maybe Later")
                                .font(FontManager.buttonText())
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32)

                    Spacer()
            }
            .padding(.top)
        }
        .navigationDestination(isPresented: $navigateToSignup) {
            SignupView()
        }
        .navigationDestination(isPresented: $navigateToPhoto) {
            PhotoPermissionView(authDestination: authDestination)
        }
        .navigationDestination(isPresented: $navigateToCamera) {
            CameraPermissionView(authDestination: authDestination)
        }
        .navigationDestination(isPresented: $navigateToLogin) {
            LoginView()
        }
        .navigationDestination(isPresented: $navigateToPostAuthSetup) {
            PostAuthSetupFlowView(onComplete: {})
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Check if notifications are already granted on appear
            permissionManager.updatePermissionStatuses()
            if permissionManager.notificationStatus == .authorized {
                // Already granted, skip to auth destination.
                goToNextPermissionOrDestination()
            }
        }
        .onChange(of: permissionManager.notificationStatus) { _, newStatus in
            if newStatus == .authorized {
                goToNextPermissionOrDestination()
            }
        }
    }

    private func goToNextPermissionOrDestination() {
        let photoGranted = permissionManager.photoStatus == .authorized || permissionManager.photoStatus == .limited
        let cameraGranted = permissionManager.cameraStatus == .authorized
        if !photoGranted {
            navigateToPhoto = true
            return
        }
        if !cameraGranted {
            navigateToCamera = true
            return
        }
        goToAuthDestination()
    }

    private func goToAuthDestination() {
        withAnimation(.easeInOut(duration: 0.25)) {}
        let delay = DispatchTime.now() + 0.12
        switch authDestination {
        case .signup:
            DispatchQueue.main.asyncAfter(deadline: delay) {
                navigateToSignup = true
            }
        case .login:
            DispatchQueue.main.asyncAfter(deadline: delay) {
                navigateToLogin = true
            }
        case .postAuthSetup:
            DispatchQueue.main.asyncAfter(deadline: delay) {
                navigateToPostAuthSetup = true
            }
        }
    }
}

#Preview {
    NotificationPermissionView()
}
