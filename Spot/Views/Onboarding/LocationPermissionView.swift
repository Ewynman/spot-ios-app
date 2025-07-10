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
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#3F7F5F"))
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal)

                    // Title
                    VStack(spacing: 8) {
                        Text("Allow")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))

                        Text("Location Access")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))
                    }

                    Text("Spot uses your location to help\nyou discover great places nearby")
                        .font(.system(size: 14, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(hex: "#2D4A3D"))

                    Spacer()

                    // Waves Image
                    Image("waves")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .padding(.horizontal, 0)

                    Spacer()

                    // Navigation trigger
                    NavigationLink(destination: NotificationPermissionView(), isActive: $navigateToNotifications) {
                        EmptyView()
                    }

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            PermissionManager.shared.requestLocationPermission()
                            navigateToNotifications = true
                        }) {
                            Text("Enable Location")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#3F7F5F"))
                                .cornerRadius(20)
                        }

                        Button(action: {
                            navigateToNotifications = true
                        }) {
                            Text("Maybe Later")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(Color(hex: "#2D4A3D"))
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .padding(.top)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    LocationPermissionView()
}
