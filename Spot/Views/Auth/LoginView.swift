//
//  LoginView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import Supabase

struct LoginView: View {
    @State private var loginIdentifier = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resetMessage: String?
    @Environment(\.dismiss) var dismiss

    private func handleLoginError(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("network") || text.contains("internet") {
            return "Network error. Please check your connection."
        }
        if text.contains("username") || text.contains("no account found") {
            return "No account found for that username."
        }
        return "Incorrect email/username or password."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Constants.Colors.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Custom Back Button
                    HStack {
                        CustomBackButton {
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Text("Log In")
                        .font(FontManager.sectionHeader())
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.top, 40)

                    // Fields with labels (match Settings style)
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email or Username")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomTextField(placeholder: "Email or Username", text: $loginIdentifier)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomSecureField(placeholder: "Password", text: $password)
                        }
                    }
                    .padding(.horizontal, 32)

                    // Forgot Password
                    HStack {
                        Spacer()
                        Button(action: {
                            let trimmed = loginIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, trimmed.contains("@") else {
                                errorMessage = "Enter your email to reset your password"
                                return
                            }
                            errorMessage = nil
                            resetMessage = nil
                            Task {
                                do {
                                    try await AuthService.shared.resetPassword(email: trimmed)
                                    SpotLogger.log(LoginViewLogs.passwordResetRequested, details: ["email": trimmed])
                                    await MainActor.run { resetMessage = "Password reset link sent. Check your email." }
                                } catch {
                                    SpotLogger.log(LoginViewLogs.passwordResetError, details: ["error": error.localizedDescription])
                                    await MainActor.run { errorMessage = "Could not send reset email. Please try again." }
                                }
                            }
                        }) {
                            Text("Forgot Password?")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32)

                    // Login Button
                    Button(action: {
                        guard !loginIdentifier.isEmpty, !password.isEmpty else {
                            errorMessage = "Please fill in all fields"
                            return
                        }

                        isLoading = true
                        errorMessage = nil

                        Task {
                            do {
                                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                                    AuthService.shared.signIn(
                                        identifier: loginIdentifier,
                                        password: password
                                    ) { result in
                                        switch result {
                                        case .success:
                                            continuation.resume(returning: ())
                                        case .failure(let error):
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                                await MainActor.run {
                                    isLoading = false
                                    SpotLogger.log(LoginViewLogs.loginSuccess)
                                    dismiss()
                                }
                            } catch {
                                await MainActor.run {
                                    isLoading = false
                                    errorMessage = handleLoginError(error)
                                    SpotLogger.log(LoginViewLogs.loginFailed, details: ["error": error.localizedDescription])
                                }
                            }
                        }
                    }) {
                        Text(isLoading ? "Logging In..." : "Login")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Constants.Colors.primary)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading)
                    .padding(.horizontal, 32)

                    ThemedAppleSignInButton(
                        onSuccess: {
                            SpotLogger.log(LoginViewLogs.loginSuccess)
                            dismiss()
                        },
                        onError: { message in
                            errorMessage = message
                            SpotLogger.log(LoginViewLogs.loginFailed, details: ["error": message])
                        }
                    )
                    .padding(.horizontal, 32)

                    // Error Text
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(FontManager.primaryText())
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .padding(.horizontal, 32)
                    }
                    // Reset success
                    if let msg = resetMessage {
                        Text(msg)
                            .foregroundColor(.green)
                            .font(FontManager.primaryText())
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .padding(.horizontal, 32)
                    }

                    // Link to Sign Up
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)

                        NavigationLink(destination: SignupView()) {
                            Text("Sign Up")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                                .buttonStyle(PlainButtonStyle())
                        }
                    }

                    Spacer()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
