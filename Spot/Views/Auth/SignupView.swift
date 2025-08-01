//
//  SignupView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

struct SignupView: View {
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreedToTerms = false
    @State private var selectedProfileImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLogin = false
    @Environment(\.dismiss) var dismiss

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
                        .onChange(of: photoPickerItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    selectedProfileImage = uiImage
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)

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
                                .foregroundColor(Constants.Colors.primary)
                        }

                        Text("I agree to the ")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary) +
                        Text("Terms Of Service")
                            .font(FontManager.primaryText())
                            .fontWeight(.semibold)
                            .foregroundColor(Constants.Colors.primary)
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

                        guard selectedProfileImage != nil else {
                            errorMessage = "Please add a profile picture."
                            return
                        }

                        isLoading = true
                        errorMessage = nil

                        // Upload profile picture first, then create user
                        uploadProfilePictureAndSignUp()
                    }) {
                        Text(isLoading ? "Signing Up..." : "Sign Up")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Constants.Colors.primary)
                            .cornerRadius(20)
                    }
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
                    }

                    Spacer()
                }

                .navigationDestination(isPresented: $showLogin) {
                    LoginView()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func uploadProfilePictureAndSignUp() {
        guard let profileImage = selectedProfileImage else { return }
        
        isLoading = true
        errorMessage = nil
        
        // First create user with empty profile picture URL
        AuthService.shared.signUp(email: email, password: password, username: username, profileImageURL: "") { result in
            switch result {
            case .success:
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
