import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var username: String = ""
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isPrivate: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var originalUsername: String = ""
    @State private var confirmDelete: Bool = false
    @State private var deletePassword: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())

                Text("Settings")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)
                    .frame(maxWidth: .infinity)

                Spacer().frame(width: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 16) {
                    sectionHeader("Account")

                    SettingsTextField(title: "Username", text: $username)
                    SettingsTextField(title: "Name", text: $name)
                    SettingsTextField(title: "Email", text: $email, keyboardType: .emailAddress)

                    sectionHeader("Password")
                    SettingsSecureField(title: "Current Password", text: $currentPassword)
                    SettingsSecureField(title: "New Password", text: $newPassword)
                    SettingsSecureField(title: "Confirm Password", text: $confirmPassword)

                    sectionHeader("Privacy")
                    Toggle(isOn: $isPrivate) {
                        Text("Private Account")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    }
                    .tint(Constants.Colors.primary)

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(FontManager.primaryText())
                            .multilineTextAlignment(.center)
                    }
                    if let success = successMessage {
                        Text(success)
                            .foregroundColor(.green)
                            .font(FontManager.primaryText())
                            .multilineTextAlignment(.center)
                    }

                    Button(action: save) {
                        Text(isSaving ? "Saving..." : "Save Changes")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Constants.Colors.primary)
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isSaving)

                    // Privacy & Account Section
                    sectionHeader("Privacy & Account")
                    
                    NavigationLink {
                        BlockedUsersView()
                    } label: {
                        Text("Blocked Users")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Constants.Colors.primary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        authVM.signOut()
                    } label: {
                        Text("Log Out")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Constants.Colors.primary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $confirmDelete) {
                            Text("I understand this will permanently delete my account")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.primary)
                        }
                        .tint(Constants.Colors.primary)

                        SettingsSecureField(title: "Password to Confirm", text: $deletePassword)

                        Button {
                            guard confirmDelete, !deletePassword.isEmpty else {
                                showToast(message: "Please confirm and enter your password", isError: true)
                                return
                            }
                            isSaving = true
                            authVM.deleteAccount(password: deletePassword) { result in
                                DispatchQueue.main.async {
                                    isSaving = false
                                    switch result {
                                    case .success:
                                        showToast(message: "Account deleted", isError: false)
                                    case .failure(let error):
                                        showToast(message: error.localizedDescription, isError: true)
                                    }
                                }
                            }
                        } label: {
                            Text("Delete Account")
                                .font(FontManager.buttonText())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: load)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let error = errorMessage {
                    ToastView(message: error, isError: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let success = successMessage {
                    ToastView(message: success, isError: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
        }
    }

    private func load() {
        guard let userId = authVM.userId else { return }
        Task {
            do {
                let snap = try await Firestore.firestore().collection("users").document(userId).getDocument()
                let data = snap.data() ?? [:]
                await MainActor.run {
                    username = data["username"] as? String ?? ""
                    originalUsername = username
                    name = data["name"] as? String ?? ""
                    email = data["email"] as? String ?? (Auth.auth().currentUser?.email ?? "")
                    isPrivate = data["isPrivate"] as? Bool ?? false
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func save() {
        errorMessage = nil
        successMessage = nil
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Username cannot be empty"
            return
        }
        if !newPassword.isEmpty || !confirmPassword.isEmpty {
            guard newPassword == confirmPassword else {
                errorMessage = "Passwords do not match"
                return
            }
            guard newPassword.count >= 6 else {
                errorMessage = "Password must be at least 6 characters"
                return
            }
        }

        isSaving = true

        // Validation
        Task {
            if username != originalUsername {
                let available = await authVM.isUsernameAvailable(username)
                if !available {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = "Username is already taken"
                    }
                    return
                }
            }
        }

        // Update Firestore profile fields
        let group = DispatchGroup()
        var firstError: Error?

        group.enter()
        authVM.updateUsername(username) { result in
            if case let .failure(err) = result { firstError = firstError ?? err }
            group.leave()
        }

        group.enter()
        authVM.updateName(name) { result in
            if case let .failure(err) = result { firstError = firstError ?? err }
            group.leave()
        }

        if !email.isEmpty && email != Auth.auth().currentUser?.email {
            // Ask user to confirm change and send verification link
            DispatchQueue.main.async {
                let newEmail = email
                // Present inline confirm style in place
                let alert = UIAlertController(title: "Confirm new email", message: "We’ll send a verification link to \(newEmail). Your email will update after you verify.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in }))
                alert.addAction(UIAlertAction(title: "Send & Verify", style: .default, handler: { _ in
                    Task {
                        do {
                            // Reauth best-effort
                            if !currentPassword.isEmpty { await withCheckedContinuation { cont in authVM.reauthenticate(currentPassword: currentPassword) { _ in cont.resume() } } }
                            try await authVM.verifyBeforeUpdateEmail(newEmail)
                            // Navigate to confirmation screen
                            if let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
                                let hosting = UIHostingController(rootView: ConfirmNewEmailView(newEmail: newEmail).environmentObject(authVM))
                                root.present(hosting, animated: true)
                            }
                        } catch {
                            firstError = firstError ?? error
                        }
                    }
                }))
                UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.present(alert, animated: true)
            }
        }

        if !newPassword.isEmpty {
            group.enter()
            authVM.reauthenticate(currentPassword: currentPassword) { _ in
                authVM.updatePassword(newPassword) { result in
                    if case let .failure(err) = result { firstError = firstError ?? err }
                    group.leave()
                }
            }
        }

        group.enter()
        authVM.setPrivateAccount(isPrivate) { result in
            if case let .failure(err) = result { firstError = firstError ?? err }
            group.leave()
        }

        group.notify(queue: .main) {
            isSaving = false
            if let err = firstError {
                showToast(message: err.localizedDescription, isError: true)
            } else {
                showToast(message: "Settings updated", isError: false)
            }
        }
    }

    private func showToast(message: String, isError: Bool) {
        if isError {
            errorMessage = message
            successMessage = nil
        } else {
            successMessage = message
            errorMessage = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                errorMessage = nil
                successMessage = nil
            }
        }
    }
}

private func sectionHeader(_ title: String) -> some View {
    HStack {
        Text(title)
            .font(FontManager.sectionHeader())
            .foregroundColor(Constants.Colors.primary)
        Spacer()
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
                .tint(Constants.Colors.primary)
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .padding()
                .foregroundColor(Constants.Colors.primary)
                .tint(Constants.Colors.primary)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Constants.Colors.primary, lineWidth: 1)
                )
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
            SecureField(title, text: $text)
                .padding()
                .foregroundColor(Constants.Colors.primary)
                .tint(Constants.Colors.primary)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Constants.Colors.primary, lineWidth: 1)
                )
        }
    }
}

#Preview {
    SettingsView()
}

// Note: Reuse the global ToastView defined in PostFlow; no local duplicate here.


