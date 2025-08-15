//
//  LocationPermissionView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct LocationPermissionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var navigateToNotifications = false

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
                            PermissionManager.shared.requestPermissionsIfNeeded()
                            navigateToNotifications = true
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
                            navigateToNotifications = true
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
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    LocationPermissionView()
}
