//
//  WelcomeView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var navigateToLocation = false
    @State private var navigateToNotifications = false
    @State private var navigateToSignup = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Image("welcome_background")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    VStack(spacing: 8) {
                        Text("SPOT")
                            .font(FontManager.logoTitle())
                            .foregroundColor(Constants.Colors.primary)

                        Text("Your Favorite Places Shared")
                            .font(FontManager.sectionHeader())
                            .foregroundColor(Constants.Colors.primary)
                    }
                    .padding(.top, 60)

                    Spacer()

                    Button(action: {
                        // Check permission status and navigate accordingly
                        permissionManager.updatePermissionStatuses()
                        let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse || permissionManager.locationStatus == .authorizedAlways
                        let notificationsGranted = permissionManager.notificationStatus == .authorized
                        
                        if locationGranted && notificationsGranted {
                            // Both granted, skip to signup
                            navigateToSignup = true
                        } else if locationGranted {
                            // Location granted, skip to notifications
                            navigateToNotifications = true
                        } else {
                            // Need location permission
                            navigateToLocation = true
                        }
                    }) {
                        Text("Get Started")
                            .font(FontManager.buttonText())
                            .frame(width: UIScreen.main.bounds.width * 0.65)
                            .padding()
                            .background(Constants.Colors.primary)
                            .foregroundColor(Constants.Colors.buttonText)
                            .cornerRadius(40)
                            .padding(.horizontal, 0)
                    }
                    .buttonStyle(PlainButtonStyle())

                    HStack {
                        Text("Already have an account?")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.buttonText)

                        Button("Login") {
                            showLogin = true
                        }
                        .font(FontManager.primaryText())
                        .fontWeight(.black)
                        .foregroundColor(Constants.Colors.buttonText)
                        .underline()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .navigationDestination(isPresented: $navigateToLocation) {
                    LocationPermissionView()
                }
                .navigationDestination(isPresented: $navigateToNotifications) {
                    NotificationPermissionView()
                }
                .navigationDestination(isPresented: $navigateToSignup) {
                    SignupView()
                }
                .navigationDestination(isPresented: $showLogin) {
                    LoginView()
                }
            }
        }
    }
}

#Preview {
    WelcomeView()
}
