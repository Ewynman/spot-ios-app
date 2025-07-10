//
//  SignupView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct SignupView: View {
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreedToTerms = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Constants.Colors.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Sign Up")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#2D4A3D"))
                        .padding(.top, 40)

                    VStack(spacing: 12) {
                        CustomTextField(placeholder: "Email", text: $email)
                        CustomTextField(placeholder: "Username", text: $username)
                        CustomSecureField(placeholder: "Password", text: $password)
                        CustomSecureField(placeholder: "Confirm password", text: $confirmPassword)
                    }
                    .padding(.horizontal, 32)

                    HStack(alignment: .center) {
                        Button(action: {
                            agreedToTerms.toggle()
                        }) {
                            Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                .foregroundColor(Color(hex: "#3F7F5F"))
                        }

                        Text("I agree to the ")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D")) +
                        Text("Terms Of Service")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                    Button(action: {
                        guard agreedToTerms else {
                            errorMessage = "Please agree to the Terms of Service."
                            return
                        }

                        guard !email.isEmpty, !username.isEmpty, !password.isEmpty else {
                            errorMessage = "Please fill in all fields."
                            return
                        }

                        guard password == confirmPassword else {
                            errorMessage = "Passwords do not match."
                            return
                        }

                        isLoading = true
                        errorMessage = nil

                        AuthService.shared.signUp(email: email, password: password, username: username) { result in
                            DispatchQueue.main.async {
                                isLoading = false
                                switch result {
                                case .success:
                                    print("✅ Signed up!")
                                    // TODO: Navigate to home view
                                case .failure(let error):
                                    errorMessage = error.localizedDescription
                                    print("❌ Signup failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    }) {
                        Text(isLoading ? "Signing Up..." : "Sign Up")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "#3F7F5F"))
                            .cornerRadius(20)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .padding(.top, 4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Color(hex: "#2D4A3D"))

                        Button(action: {
                            showLogin = true
                        }) {
                            Text("Log in")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#2D4A3D"))
                        }
                    }

                    Spacer()
                }

                NavigationLink(destination: LoginView(), isActive: $showLogin) {
                    EmptyView()
                }
                .hidden()
            }
        }
    }
}


// MARK: - Custom Reusable Fields

struct CustomTextField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding()
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#2D4A3D"), lineWidth: 1)
            )
            .font(.system(size: 14, design: .rounded))
            .autocapitalization(.none)
            .textInputAutocapitalization(.never)
    }
}

struct CustomSecureField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .padding()
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#2D4A3D"), lineWidth: 1)
            )
            .font(.system(size: 14, design: .rounded))
    }
}

#Preview {
    SignupView()
}
