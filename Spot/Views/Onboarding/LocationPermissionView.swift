//
//  LocationPermissionView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct LocationPermissionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var navigateToNotifications = false
    @State private var navigateToSignup = false

    var body: some View {
        NavigationStack {
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
                                navigateToSignup = true
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
                NotificationPermissionView()
            }
            .navigationDestination(isPresented: $navigateToSignup) {
                SignupView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Check if location is already granted on appear
            permissionManager.updatePermissionStatuses()
            let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse || permissionManager.locationStatus == .authorizedAlways
            let notificationsGranted = permissionManager.notificationStatus == .authorized
            
            if locationGranted && notificationsGranted {
                // Both granted, skip to signup
                navigateToSignup = true
            } else if locationGranted {
                // Location granted, skip to notifications
                navigateToNotifications = true
            }
        }
        .onChange(of: permissionManager.locationStatus) { _, newStatus in
            if newStatus != .notDetermined {
                // Check if notifications are already granted
                permissionManager.updatePermissionStatuses()
                if permissionManager.notificationStatus == .authorized {
                    navigateToSignup = true
                } else {
                    navigateToNotifications = true
                }
            }
        }
    }
}

#Preview {
    LocationPermissionView()
}
