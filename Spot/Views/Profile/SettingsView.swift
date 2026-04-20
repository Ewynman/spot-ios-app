import SwiftUI
import PhotosUI
import UIKit

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
    @State private var currentPasswordError: String?
    @State private var newPasswordError: String?
    @State private var confirmPasswordError: String?
    @State private var originalUsername: String = ""
    @State private var confirmDelete: Bool = false
    @State private var deletePassword: String = ""
    @State private var profileImageURL: String?
    @State private var selectedProfileImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto: Bool = false
    @State private var showCollectionsNav: Bool = false

    private struct SettingsUserRow: Decodable {
        let username: String
        let email: String?
        let is_private: Bool
        let profile_image_url: String?
    }

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
                VStack(spacing: 24) {
                    // MARK: - Profile Section
                    settingsSection {
                        VStack(spacing: 16) {
                            sectionHeader("Profile")
                            
                            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                ZStack {
                                    if let image = selectedProfileImage {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                                    } else if let urlString = profileImageURL, let url = URL(string: urlString) {
                                        AsyncImage(url: url) { img in
                                            img.resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(Constants.Colors.primary)
                                        }
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

                                    if isUploadingPhoto {
                                        Circle()
                                            .fill(Color.black.opacity(0.15))
                                            .frame(width: 100, height: 100)
                                        ProgressView()
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onChange(of: photoPickerItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        selectedProfileImage = uiImage
                                        uploadProfilePhoto(uiImage)
                                    }
                                }
                            }
                            
                            SettingsTextField(title: "Username", text: $username)
                            SettingsTextField(title: "Name", text: $name)
                            SettingsTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                        }
                    }
                    
                    // MARK: - Security Section
                    settingsSection {
                        VStack(spacing: 16) {
                            sectionHeader("Security")
                            
                            SettingsSecureField(title: "Current Password", text: $currentPassword)
                            if let currentPasswordError {
                                Text(currentPasswordError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            SettingsSecureField(title: "New Password", text: $newPassword)
                            if let newPasswordError {
                                Text(newPasswordError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            SettingsSecureField(title: "Confirm Password", text: $confirmPassword)
                            if let confirmPasswordError {
                                Text(confirmPasswordError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Toggle(isOn: $isPrivate) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Private Account")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                    Text("Only approved followers can see your spots")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
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
                                    .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isSaving)
                        }
                    }
                    
                    // MARK: - Subscription Management Section
                    settingsSection {
                        VStack(spacing: 12) {
                            sectionHeader("Subscription Management")

                            if authVM.isPro {
                                // Show Pro Until date prominently
                                HStack(spacing: 12) {
                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(Constants.Colors.primary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pro Member")
                                            .font(FontManager.primaryText())
                                            .foregroundColor(Constants.Colors.primary)
                                        if let proUntil = authVM.proUntil {
                                            Text("Active until \(formatDate(proUntil))")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)

                                Button {
                                    showCollectionsNav = true
                                } label: {
                                    settingsRow(title: "Bookmark Collections", icon: "bookmark.fill", subtitle: "Pro")
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button {
                                    Task {
                                        do {
                                            try await SubscriptionManager.shared.manageSubscriptions()
                                        } catch {
                                            await MainActor.run {
                                                showToast(message: error.localizedDescription, isError: true)
                                            }
                                        }
                                    }
                                } label: {
                                    settingsRow(title: "Manage Subscription", icon: "creditcard.fill")
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                Button {
                                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                                } label: {
                                    settingsRow(title: "Go Pro", icon: "star.fill")
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button {
                                    Task {
                                        do {
                                            try await SubscriptionManager.shared.restorePurchases()
                                            if await SubscriptionManager.shared.refreshEntitlement() {
                                                let expirationDate = await SubscriptionManager.shared.refreshEntitlementExpiry()
                                                await authVM.setProActive(true, proUntil: expirationDate)
                                                await MainActor.run {
                                                    showToast(message: "Subscription restored", isError: false)
                                                }
                                            } else {
                                                await MainActor.run {
                                                    showToast(message: "No active subscription found", isError: true)
                                                }
                                            }
                                        } catch {
                                            await MainActor.run {
                                                showToast(message: error.localizedDescription, isError: true)
                                            }
                                        }
                                    }
                                } label: {
                                    settingsRow(title: "Restore Purchases", icon: "arrow.clockwise")
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }

                    // MARK: - Account Privacy Section
                    settingsSection {
                        VStack(spacing: 12) {
                            sectionHeader("Account Privacy")

                            NavigationLink {
                                BlockedUsersView()
                            } label: {
                                settingsRow(title: "Blocked Users", icon: "person.slash.fill")
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // MARK: - Danger Zone Section
                    settingsSection {
                        VStack(spacing: 16) {
                            sectionHeader("Danger Zone")
                            
                            Button {
                                authVM.signOut()
                            } label: {
                                settingsRow(title: "Log Out", icon: "arrow.right.square.fill", isDestructive: false)
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
                                    settingsRow(title: "Delete Account", icon: "trash.fill", isDestructive: true)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!confirmDelete || deletePassword.isEmpty)
                            }
                        }
                    }
                    
                    // MARK: - Legal Section
                    settingsSection {
                        VStack(spacing: 12) {
                            sectionHeader("Legal")
                            
                            Button {
                                if let url = URL(string: "https://spotapp.online/terms") { UIApplication.shared.open(url) }
                            } label: {
                                settingsRow(title: "Terms & Conditions", icon: "doc.text.fill")
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                if let url = URL(string: "https://spotapp.online/privacy") { UIApplication.shared.open(url) }
                            } label: {
                                settingsRow(title: "Privacy Policy", icon: "lock.shield.fill")
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: load)
        .navigationDestination(isPresented: $showCollectionsNav) {
            CollectionsView()
        }
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
        .task {
            load()
        }
    }

    private func load() {
        guard let userId = authVM.userId, let uid = UUID(uuidString: userId) else { return }
        Task {
            do {
                let row: SettingsUserRow = try await supabase
                    .from("users")
                    .select("username,email,is_private,profile_image_url")
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value
                let authUser = try? await supabase.auth.user()
                await MainActor.run {
                    username = row.username
                    originalUsername = username
                    name = (authUser?.userMetadata["full_name"]?.stringValue) ?? ""
                    email = row.email ?? (authUser?.email ?? SpotAuthBridge.currentUserEmail ?? "")
                    isPrivate = row.is_private
                    profileImageURL = row.profile_image_url
                }
            } catch {
                SpotLogger.log(SettingsViewLogs.loadProfileFailed, details: ["userId": userId, "error": error.localizedDescription])
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func save() {
        errorMessage = nil
        successMessage = nil
        currentPasswordError = nil
        newPasswordError = nil
        confirmPasswordError = nil
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Username cannot be empty"
            return
        }
        if !newPassword.isEmpty || !confirmPassword.isEmpty {
            guard newPassword == confirmPassword else {
                confirmPasswordError = "Passwords do not match."
                return
            }
            switch PasswordValidator.validate(newPassword) {
            case .ok:
                break
            case .failure(let message):
                newPasswordError = message
                return
            }
        }
        let isEmailChange = !email.isEmpty && email != SpotAuthBridge.currentUserEmail
        let isPasswordChange = !newPassword.isEmpty
        if (isEmailChange || isPasswordChange) &&
            currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentPasswordError = "Current password is required for email or password changes."
            return
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

        // Update Supabase profile fields
        let group = DispatchGroup()
        var firstError: Error?

        // Username validation before updating
        let validator = UsernameValidator()
        switch validator.validate(username) {
        case .ok: break
        case .tooShort: isSaving = false; errorMessage = "Username is too short"; return
        case .tooLong: isSaving = false; errorMessage = "Username is too long"; return
        case .invalidChars: isSaving = false; errorMessage = "Username has invalid characters"; return
        case .reserved: isSaving = false; errorMessage = "That username is reserved"; return
        case .blocked:
            SpotLogger.log(SettingsViewLogs.usernameBlocked, details: ["raw": username, "norm": validator.normalized(username)])
            isSaving = false; errorMessage = "That username isn’t allowed"; return
        }

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

        if isEmailChange {
            // Ask user to confirm change and send verification link
            DispatchQueue.main.async {
                let newEmail = email
                // Present inline confirm style in place
                let alert = UIAlertController(title: "Confirm new email", message: "We’ll send a verification link to \(newEmail). Your email will update after you verify.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in }))
                alert.addAction(UIAlertAction(title: "Send & Verify", style: .default, handler: { _ in
                    Task {
                        do {
                            // Enforce current-password reauth before any email change.
                            let reauthResult: Result<Void, Error> = await withCheckedContinuation { cont in
                                authVM.reauthenticate(currentPassword: currentPassword) { result in
                                    cont.resume(returning: result)
                                }
                            }
                            if case let .failure(reauthError) = reauthResult {
                                throw reauthError
                            }
                            try await authVM.verifyBeforeUpdateEmail(newEmail)
                            // Navigate to confirmation screen
                            // Use SwiftUI navigation push via a navigation state instead of presenting UIKit controller
                            // Fallback: show a lightweight toast to prompt user to check inbox
                            successMessage = "Verification email sent. Check your inbox."
                        } catch {
                            SpotLogger.log(SettingsViewLogs.verifyBeforeUpdateEmailFailed, details: ["newEmail": newEmail, "error": error.localizedDescription])
                            firstError = firstError ?? error
                        }
                    }
                }))
                UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?.present(alert, animated: true)
            }
        }

        if isPasswordChange {
            group.enter()
            authVM.reauthenticate(currentPassword: currentPassword) { reauth in
                switch reauth {
                case .failure(let error):
                    firstError = firstError ?? error
                    group.leave()
                case .success:
                    authVM.updatePassword(newPassword) { result in
                        if case let .failure(err) = result { firstError = firstError ?? err }
                        group.leave()
                    }
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
                SpotLogger.log(SettingsViewLogs.saveFailed, details: ["error": err.localizedDescription])
                showToast(message: err.localizedDescription, isError: true)
            } else {
                SpotLogger.log(SettingsViewLogs.saveSuccess, details: [
                    "usernameChanged": username != originalUsername,
                    "emailChanged": email != SpotAuthBridge.currentUserEmail ?? "",
                    "isPrivate": isPrivate
                ])
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func uploadProfilePhoto(_ image: UIImage) {
        SpotLogger.log(SettingsViewLogs.profilePhotoUploadStart)
        isUploadingPhoto = true
        errorMessage = nil
        successMessage = nil
        guard let uid = SpotAuthBridge.currentUserId, let uuid = UUID(uuidString: uid) else {
            isUploadingPhoto = false
            showToast(message: "No user session", isError: true)
            SpotLogger.log(SettingsViewLogs.profilePhotoUploadNoUser)
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            isUploadingPhoto = false
            showToast(message: "Failed to process image", isError: true)
            SpotLogger.log(SettingsViewLogs.profilePhotoUploadFailed, details: ["error": "JPEG conversion failed"])
            return
        }
        Task {
            do {
                struct AvatarPatch: Encodable { let profile_image_url: String }
                let url = try await SupabaseUserService.shared.uploadProfileAvatarJPEG(data, userId: uuid)
                try await supabase
                    .from("users")
                    .update(AvatarPatch(profile_image_url: url))
                    .eq("id", value: uuid)
                    .execute()
                await MainActor.run {
                    isUploadingPhoto = false
                    profileImageURL = url
                    selectedProfileImage = nil
                    showToast(message: "Profile photo updated", isError: false)
                    SpotLogger.log(SettingsViewLogs.profilePhotoUpdated)
                }
            } catch {
                await MainActor.run {
                    isUploadingPhoto = false
                    showToast(message: "Failed to update profile picture: \(error.localizedDescription)", isError: true)
                    SpotLogger.log(SettingsViewLogs.profilePhotoUpdateSupabaseFailed, details: ["error": error.localizedDescription])
                }
            }
        }
    }
}

private func sectionHeader(_ title: String) -> some View {
    HStack {
        Text(title)
            .font(FontManager.sectionHeader())
            .fontWeight(.semibold)
            .foregroundColor(Constants.Colors.primary)
        Spacer()
    }
}

private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        content()
    }
    .padding(16)
    .background(Color.white)
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
}

private func settingsRow(title: String, icon: String, subtitle: String? = nil, isDestructive: Bool = false) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundColor(isDestructive ? .red : Constants.Colors.primary)
            .frame(width: 24)
        
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(isDestructive ? .red : Constants.Colors.primary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        
        Spacer()
        
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.gray)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(isDestructive ? Color.red.opacity(0.1) : Color.clear)
    .cornerRadius(8)
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
