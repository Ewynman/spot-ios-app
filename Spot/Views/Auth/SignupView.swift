//
//  SignupView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import UIKit
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

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
    @State private var showLogin = false
    @State private var showConfirmEmail = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showPaywall: Bool = false

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
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Confirm Password")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                            CustomSecureField(placeholder: "Confirm password", text: $confirmPassword)
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

                    // Compare Free vs Pro
                    Button(action: { showPaywall = true }) {
                        Text("Compare Free vs Pro")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                            .underline()
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        guard agreedToTerms else {
                            errorMessage = "Please agree to the Terms of Service."
                            return
                        }

                        guard !email.isEmpty, !username.isEmpty, !password.isEmpty else {
                            errorMessage = "Please fill in all fields."
                            return
                        }

                        // Username validation (client-fast)
                        let validator = UsernameValidator()
                        switch validator.validate(username) {
                        case .ok:
                            break
                        case .tooShort:
                            errorMessage = "Username is too short"; return
                        case .tooLong:
                            errorMessage = "Username is too long"; return
                        case .invalidChars:
                            errorMessage = "Username has invalid characters"; return
                        case .reserved:
                            errorMessage = "That username is reserved"; return
                        case .blocked:
                            SpotLogger.debug(.auth, "Username blocked", details: ["raw": username, "norm": validator.normalized(username), "reason": "blocked"])
                            errorMessage = "That username isn’t allowed"; return
                        }

                        guard password == confirmPassword else {
                            errorMessage = "Passwords do not match."
                            return
                        }

                        guard selectedProfileImage != nil else {
                            errorMessage = "Please add a profile picture."
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

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(FontManager.primaryText())
                            .padding(.top, 4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

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
                .navigationDestination(isPresented: $showConfirmEmail) {
                    ConfirmEmailView()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(authVM)
        }
    }

    private func validateAndSignUp() {
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("users")
                    .whereField("username", isEqualTo: username)
                    .limit(to: 1)
                    .getDocuments()
                if !snapshot.documents.isEmpty {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "Username is already taken"
                    }
                    return
                }
                // Proceed with signup flow
                await MainActor.run { self.uploadProfilePictureAndSignUp() }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to validate username. Please try again."
                }
            }
        }
    }

    private func uploadProfilePictureAndSignUp() {
        guard let profileImage = selectedProfileImage else { return }

        isLoading = true
        errorMessage = nil

        // First create user with empty profile picture URL
        AuthService.shared.signUp(email: email, password: password, username: username, profileImageURL: "", isPrivate: isPrivate) { result in
            switch result {
            case .success:
                // Update Firebase Auth display name to keep in sync
                if let changeReq = Auth.auth().currentUser?.createProfileChangeRequest() {
                    changeReq.displayName = self.username
                    changeReq.commitChanges(completion: nil)
                }
                // Send verification email and push confirm screen (using shared VM)
                Task { await authVM.sendVerificationEmail() }
                DispatchQueue.main.async { self.showConfirmEmail = true }
                // Now that we're authenticated, upload the profile picture
                ProfilePictureUploader.shared.uploadProfilePicture(image: profileImage) { uploadResult in
                    DispatchQueue.main.async {
                        switch uploadResult {
                        case .success(let imageURL):
                            // Update the user's document with the profile picture URL
                            guard let uid = Auth.auth().currentUser?.uid else {
                                self.isLoading = false
                                self.errorMessage = "Failed to get user ID"
                                return
                            }

                            let userData: [String: Any] = [
                                "profileImageURL": imageURL
                            ]

                            Firestore.firestore().collection("users").document(uid).updateData(userData) { error in
                                self.isLoading = false
                                if let error = error {
                                    self.errorMessage = "Failed to update profile picture: \(error.localizedDescription)"
                                } else {
                                    print("✅ Signed up and uploaded profile picture!")
                                }
                            }
                        case .failure(let error):
                            self.isLoading = false
                            self.errorMessage = "Failed to upload profile picture: \(error.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    print("❌ Signup failed: \(error.localizedDescription)")
                }
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
}
