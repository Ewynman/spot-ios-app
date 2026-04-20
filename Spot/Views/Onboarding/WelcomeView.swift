//
//  WelcomeView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct WelcomeView: View {
    private enum AuthDestination {
        case signup
        case login
    }

    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var navigateToLocation = false
    @State private var navigateToNotifications = false
    @State private var navigateToSignup = false
    @State private var navigateToLogin = false
    @State private var authDestination: AuthDestination = .signup
    @State private var appleErrorMessage: String?

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
                        startOnboardingFlow(destination: .signup)
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
                    .padding(.bottom, 6)

                    ThemedAppleSignInButton(
                        onSuccess: {
                            // Root auth gate will transition automatically from auth state.
                        },
                        onError: { message in
                            appleErrorMessage = message
                        },
                        height: 56
                    )
                    .frame(width: UIScreen.main.bounds.width * 0.65)
                    .padding(.horizontal, 0)

                    HStack {
                        Text("Already have an account?")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.buttonText)

                        Button("Login") {
                            navigateToLogin = true
                        }
                        .font(FontManager.primaryText())
                        .fontWeight(.black)
                        .foregroundColor(Constants.Colors.buttonText)
                        .underline()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    if let appleErrorMessage {
                        Text(appleErrorMessage)
                            .font(FontManager.primaryText())
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .navigationDestination(isPresented: $navigateToLocation) {
                    LocationPermissionView(authDestination: authDestination == .login ? .login : .signup)
                        .environmentObject(permissionManager)
                }
                .navigationDestination(isPresented: $navigateToNotifications) {
                    NotificationPermissionView(authDestination: authDestination == .login ? .login : .signup)
                        .environmentObject(permissionManager)
                }
                .navigationDestination(isPresented: $navigateToSignup) {
                    SignupView()
                }
                .navigationDestination(isPresented: $navigateToLogin) {
                    LoginView()
                }
            }
        }
    }

    private func startOnboardingFlow(destination: AuthDestination) {
        authDestination = destination
        permissionManager.updatePermissionStatuses()
        let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse || permissionManager.locationStatus == .authorizedAlways
        let notificationsGranted = permissionManager.notificationStatus == .authorized

        if locationGranted && notificationsGranted {
            routeToDestination(destination)
        } else if locationGranted {
            navigateToNotifications = true
        } else {
            navigateToLocation = true
        }
    }

    private func routeToDestination(_ destination: AuthDestination) {
        switch destination {
        case .signup:
            navigateToSignup = true
        case .login:
            navigateToLogin = true
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthViewModel())
}
