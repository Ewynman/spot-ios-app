import SwiftUI
import PhotosUI
import Supabase

struct PostAuthSetupFlowView: View {
    @EnvironmentObject var authVM: AuthViewModel

    let onComplete: () -> Void

    @State private var username: String = ""
    @State private var originalUsername: String = ""
    @State private var selectedProfileImage: UIImage?
    @State private var existingProfileImageURL: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isSavingProfile: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 16)

            profileStep

            if let errorMessage {
                Text(errorMessage)
                    .font(FontManager.primaryText())
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.background.ignoresSafeArea())
        .task {
            await loadCurrentProfile()
        }
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedProfileImage = image
                }
            }
        }
    }

    private var profileStep: some View {
        VStack(spacing: 16) {
            Text("Complete Your Profile")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)
            Text("Confirm your username and add a profile photo to continue.")
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ZStack {
                    if let image = selectedProfileImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                    } else if let existingProfileImageURL, let url = URL(string: existingProfileImageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 104, height: 104)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                            default:
                                Circle()
                                    .fill(Constants.Colors.background)
                                    .frame(width: 104, height: 104)
                                    .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 38))
                                            .foregroundColor(Constants.Colors.primary)
                                    )
                            }
                        }
                    } else {
                        Circle()
                            .fill(Constants.Colors.background)
                            .frame(width: 104, height: 104)
                            .overlay(Circle().stroke(Constants.Colors.primary, lineWidth: 2))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(Constants.Colors.primary)
                            )
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            SettingsTextField(title: "Username", text: $username)
                .padding(.horizontal, 32)

            Button {
                Task { await saveProfileAndContinue() }
            } label: {
                Text(isSavingProfile ? "Saving..." : "Continue")
                    .font(FontManager.buttonText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Constants.Colors.primary)
                    .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isSavingProfile)
            .padding(.horizontal, 32)
        }
    }

    private func loadCurrentProfile() async {
        guard let uidString = authVM.userId, let uid = UUID(uuidString: uidString) else { return }
        struct Row: Decodable {
            let username: String
            let profile_image_url: String?
        }
        if let row: Row = try? await supabase
            .from("users")
            .select("username,profile_image_url")
            .eq("id", value: uid)
            .single()
            .execute()
            .value {
            await MainActor.run {
                username = row.username
                originalUsername = row.username
                existingProfileImageURL = row.profile_image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    @MainActor
    private func saveProfileAndContinue() async {
        errorMessage = nil
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Username is required."
            return
        }
        guard selectedProfileImage != nil || !(existingProfileImageURL?.isEmpty ?? true) else {
            errorMessage = "Profile picture is required."
            return
        }
        guard let uidString = authVM.userId, let uid = UUID(uuidString: uidString) else {
            errorMessage = "No authenticated user."
            return
        }

        let validator = UsernameValidator()
        switch validator.validate(trimmed) {
        case .ok: break
        case .tooShort: errorMessage = "Username is too short."; return
        case .tooLong: errorMessage = "Username is too long."; return
        case .invalidChars: errorMessage = "Username has invalid characters."; return
        case .reserved: errorMessage = "That username is reserved."; return
        case .blocked: errorMessage = "That username isn’t allowed."; return
        }

        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            if trimmed.lowercased() != originalUsername.lowercased() {
                let available = await authVM.isUsernameAvailable(trimmed)
                if !available {
                    errorMessage = "Username is already taken."
                    return
                }
            }

            var avatarURLToPersist = existingProfileImageURL
            if let image = selectedProfileImage {
                guard let data = image.jpegData(compressionQuality: 0.7) else {
                    errorMessage = "Failed to process image."
                    return
                }
                avatarURLToPersist = try await SupabaseUserService.shared.uploadProfileAvatarJPEG(data, userId: uid)
            }

            struct Patch: Encodable {
                let username: String
                let username_lower: String
                let profile_image_url: String?
            }

            try await supabase
                .from("users")
                .update(Patch(
                    username: trimmed,
                    username_lower: trimmed.lowercased(),
                    profile_image_url: avatarURLToPersist
                ))
                .eq("id", value: uid)
                .execute()

            // Best-effort: keep auth metadata in sync for clients that read username there.
            do {
                _ = try await supabase.auth.update(
                    user: UserAttributes(
                        data: ["username": .string(trimmed)]
                    )
                )
            } catch {
                // `users` row is already updated; continuing avoids blocking the user on auth-only failures.
            }

            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PostAuthSetupFlowView(onComplete: {})
        .environmentObject(AuthViewModel())
        .environmentObject(PermissionManager.shared)
}
