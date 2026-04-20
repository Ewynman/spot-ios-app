//
//  LocationPermissionView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct LocationPermissionView: View {
    enum AuthDestination {
        case signup
        case login
        case postAuthSetup
    }

    let authDestination: AuthDestination
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var navigateToNotifications = false
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

                        Text("Location Access")
                            .font(FontManager.sectionHeader())
                            .foregroundColor(Constants.Colors.primary)
                    }

                    Text("Spot uses your location to help\nyou discover great places nearby")
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
                            permissionManager.requestLocationPermission()
                        }) {
                            Text("Enable Location")
                                .font(FontManager.buttonText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Constants.Colors.primary)
                                .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            // Check if notifications are already granted
                            permissionManager.updatePermissionStatuses()
                            if permissionManager.notificationStatus == .authorized {
                                goToAuthDestination()
                            } else {
                                navigateToNotifications = true
                            }
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
        .navigationDestination(isPresented: $navigateToNotifications) {
            NotificationPermissionView(authDestination: {
                switch authDestination {
                case .signup: return .signup
                case .login: return .login
                case .postAuthSetup: return .postAuthSetup
                }
            }())
        }
        .navigationDestination(isPresented: $navigateToSignup) {
            SignupView()
        }
        .navigationDestination(isPresented: $navigateToLogin) {
            LoginView()
        }
        .navigationDestination(isPresented: $navigateToPostAuthSetup) {
            PostAuthSetupFlowView(onComplete: {})
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Check if location is already granted on appear
            permissionManager.updatePermissionStatuses()
            let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse || permissionManager.locationStatus == .authorizedAlways
            let notificationsGranted = permissionManager.notificationStatus == .authorized
            
            if locationGranted && notificationsGranted {
                // Both granted, skip to destination
                goToAuthDestination()
            } else if locationGranted {
                // Location granted, skip to notifications
                pushToNotifications()
            }
        }
        .onChange(of: permissionManager.locationStatus) { _, newStatus in
            if newStatus != .notDetermined {
                // Check if notifications are already granted
                permissionManager.updatePermissionStatuses()
                if permissionManager.notificationStatus == .authorized {
                    goToAuthDestination()
                } else {
                    pushToNotifications()
                }
            }
        }
    }

    private func goToAuthDestination() {
        switch authDestination {
        case .signup:
            navigateToSignup = true
        case .login:
            navigateToLogin = true
        case .postAuthSetup:
            navigateToPostAuthSetup = true
        }
    }

    private func pushToNotifications() {
        withAnimation(.easeInOut(duration: 0.25)) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            navigateToNotifications = true
        }
    }
}

#Preview {
    LocationPermissionView()
}
