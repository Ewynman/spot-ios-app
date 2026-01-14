//
//  NotificationPermissionView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
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
                            permissionManager.requestNotificationPermission()
                        }) {
                            Text("Allow Notifications")
                                .font(FontManager.buttonText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Constants.Colors.primary)
                                .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            navigateToSignup = true
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
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Check if notifications are already granted on appear
            permissionManager.updatePermissionStatuses()
            if permissionManager.notificationStatus == .authorized {
                // Already granted, skip to signup
                navigateToSignup = true
            }
        }
        .onChange(of: permissionManager.notificationStatus) { _, newStatus in
            if newStatus != .notDetermined {
                navigateToSignup = true
            }
        }
    }
}

#Preview {
    NotificationPermissionView()
}
