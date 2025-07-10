//
//  LoginView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var isLoggedIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                Constants.Colors.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Log In")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#2D4A3D"))
                        .padding(.top, 40)

                    // Fields
                    VStack(spacing: 12) {
                        CustomTextField(placeholder: "Email", text: $email)
                        CustomSecureField(placeholder: "Password", text: $password)
                    }
                    .padding(.horizontal, 32)

                    // Login Button
                    Button(action: {
                        guard !email.isEmpty, !password.isEmpty else {
                            errorMessage = "Please fill in all fields."
                            return
                        }

                        isLoading = true
                        errorMessage = nil

                        AuthService.shared.signIn(email: email, password: password) { result in
                            DispatchQueue.main.async {
                                isLoading = false
                                switch result {
                                case .success:
                                    print("✅ Logged in")
                                    isLoggedIn = true
                                case .failure(let error):
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }) {
                        Text(isLoading ? "Logging In..." : "Login")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "#3F7F5F"))
                            .cornerRadius(20)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 32)

                    // Error Text
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .padding(.horizontal, 32)
                    }

                    // Link to Sign Up
                    HStack(spacing: 4) {
                        Text("Don’t have an account?")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))

                        NavigationLink(destination: SignupView()) {
                            Text("Sign Up")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#2D4A3D"))
                        }
                    }

                    Spacer()
                }

                NavigationLink(destination: HomeView(), isActive: $isLoggedIn) {
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    LoginView()
}
