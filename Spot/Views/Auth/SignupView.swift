//
//  SignupView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import UIKit
import PhotosUI
import Supabase

struct SignupView: View {
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreedToTerms = false
    @State private var isPrivate = false
    @State private var selectedProfileImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var passwordError: String?
    @State private var confirmPasswordError: String?
    @State private var toastMessage: String?
    @State private var toastIsError: Bool = true
    @State private var showLogin = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

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

                    Text("Sign Up")
                        .font(FontManager.sectionHeader())
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.top, 40)

                    // Profile Picture Picker
                    VStack(spacing: 12) {
                        Text("Add Profile Picture")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)

                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            ZStack {
                                if let image = selectedProfileImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                                } else {
                                    Circle()
                                        .fill(Constants.Colors.background)
                                        .frame(width: 100, height: 100)
                                        .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(Constants.Colors.primary)
                                        )
                                }
                            }
                        }
                        .onChange(of: photoPickerItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    selectedProfileImage = uiImage
                                }
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 32)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomTextField(placeholder: "Email", text: $email)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomTextField(placeholder: "Username", text: $username)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomSecureField(placeholder: "Password", text: $password)
                            if let passwordError {
                                Text(passwordError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Confirm Password")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomSecureField(placeholder: "Confirm password", text: $confirmPassword)
                            if let confirmPasswordError {
                                Text(confirmPasswordError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            Button(action: { isPrivate.toggle() }) {
                                Image(systemName: isPrivate ? "checkmark.square.fill" : "square")
                                    .foregroundColor(Constants.Colors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Text("Private account")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                                .buttonStyle(PlainButtonStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 32)

                    HStack(alignment: .center, spacing: 6) {
                        Button(action: {
                            agreedToTerms.toggle()
                        }) {
                            Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("I agree to the ")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)

                        Button(action: { if let url = URL(string: "https://spotapp.online/terms") { UIApplication.shared.open(url) } }) {
                            Text("Terms & Conditions")
                                .font(FontManager.primaryText())
                                .fontWeight(.semibold)
                                .foregroundColor(Constants.Colors.primary)
                                .underline()
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("and")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)

                        Button(action: { if let url = URL(string: "https://spotapp.online/privacy") { UIApplication.shared.open(url) } }) {
                            Text("Privacy Policy")
                                .font(FontManager.primaryText())
                                .fontWeight(.semibold)
                                .foregroundColor(Constants.Colors.primary)
                                .underline()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                    Button(action: {
                        passwordError = nil
                        confirmPasswordError = nil
                        guard agreedToTerms else {
                            showToast("Please agree to the Terms of Service.", isError: true)
                            return
                        }

                        guard !email.isEmpty, !username.isEmpty, !password.isEmpty else {
                            showToast("Please fill in all fields.", isError: true)
                            return
                        }

                        // Username validation (client-fast)
                        let validator = UsernameValidator()
                        switch validator.validate(username) {
                        case .ok:
                            break
                        case .tooShort:
                            showToast("Username is too short", isError: true); return
                        case .tooLong:
                            showToast("Username is too long", isError: true); return
                        case .invalidChars:
                            showToast("Username has invalid characters", isError: true); return
                        case .reserved:
                            showToast("That username is reserved", isError: true); return
                        case .blocked:
                            SpotLogger.log(SignupViewLogs.usernameBlocked, details: ["raw": username, "norm": validator.normalized(username), "reason": "blocked"])
                            showToast("That username isn’t allowed", isError: true); return
                        }

                        guard password == confirmPassword else {
                            confirmPasswordError = "Passwords do not match."
                            return
                        }

                        switch PasswordValidator.validate(password) {
                        case .ok:
                            break
                        case .failure(let message):
                            passwordError = message
                            return
                        }

                        guard selectedProfileImage != nil else {
                            showToast("Please add a profile picture.", isError: true)
                            return
                        }

                        isLoading = true
                        errorMessage = nil

                        // Validate username uniqueness, then upload & sign up
                        validateAndSignUp()
                    }) {
                        Text(isLoading ? "Signing Up..." : "Sign Up")
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
                    .padding(.top, 8)

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)

                        Button(action: {
                            showLogin = true
                        }) {
                            Text("Log in")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()
                }

                .navigationDestination(isPresented: $showLogin) {
                    LoginView()
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    ToastView(message: toastMessage, isError: toastIsError)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func validateAndSignUp() {
        Task {
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let available = await authVM.isUsernameAvailable(trimmedUsername)
            if !available {
                await MainActor.run {
                    self.isLoading = false
                    self.showToast("Username is already taken", isError: true)
                }
                return
            }
            await MainActor.run { self.signUpWithSupabase() }
        }
    }

    private func signUpWithSupabase() {
        guard selectedProfileImage != nil else { return }

        isLoading = true
        errorMessage = nil

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let response = try await supabase.auth.signUp(
                    email: cleanEmail,
                    password: password,
                    data: [
                        "username": .string(trimmedUsername),
                        "is_private": .bool(isPrivate)
                    ]
                )

                await MainActor.run {
                    AnalyticsService.shared.setUserId(response.user.id.uuidString)
                    AnalyticsService.shared.logEvent("user_signup", parameters: [
                        "email_verified": response.user.emailConfirmedAt != nil
                    ])
                }

                await MainActor.run {
                    authVM.beginEmailVerificationPending(email: cleanEmail, avatar: selectedProfileImage)
                    self.isLoading = false
                    self.errorMessage = nil
                    self.showToast("Check your email for the verification code.", isError: false)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.showToast(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func showToast(_ message: String, isError: Bool) {
        withAnimation {
            toastMessage = message
            toastIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
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
            .background(Constants.Colors.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Constants.Colors.primary, lineWidth: 1)
            )
            .font(FontManager.primaryText())
            .foregroundColor(Constants.Colors.primary)
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
            .background(Constants.Colors.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Constants.Colors.primary, lineWidth: 1)
            )
            .font(FontManager.primaryText())
            .foregroundColor(Constants.Colors.primary)
    }
}

#Preview {
    SignupView()
        .environmentObject(AuthViewModel())
}
