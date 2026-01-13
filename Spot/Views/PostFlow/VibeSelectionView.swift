import SwiftUI

struct VibeSelectionView: View {
    @Binding var selectedVibe: String
    @EnvironmentObject var authVM: AuthViewModel
    @State private var customVibe: String = ""
    @State private var validationMessage: String?

    private let vibeTags = Constants.VibeTags.defaultTags

    var body: some View {
        VStack(spacing: Constants.Layout.Spacing.extraLarge) {
            // Header
            VStack(spacing: 8) {
                Text("Pick Your Vibe")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                Text("Select one vibe that best captures the mood or feeling of your spot. It helps others understand the experience in a glance.")
                    .font(FontManager.primaryText())
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Constants.Layout.Padding.horizontal)

            // Vibe Tags Grid
            ScrollView {
                // User custom vibe tags (Pro)
                if authVM.isPro, !authVM.customVibeTags.isEmpty {
                    VStack(alignment: .leading, spacing: Constants.Layout.Spacing.small) {
                        Text("Your tags")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                            .padding(.horizontal, Constants.Layout.Padding.horizontal)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: Constants.Layout.Spacing.medium) {
                            ForEach(authVM.customVibeTags, id: \.self) { vibe in
                                VibeTagButton(
                                    vibe: vibe,
                                    isSelected: selectedVibe == vibe,
                                    onTap: {
                                        SpotLogger.info("User selected vibe: \(vibe)")
                                        selectedVibe = vibe
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, Constants.Layout.Padding.horizontal)
                    }
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(vibeTags, id: \.self) { vibe in
                        VibeTagButton(
                            vibe: vibe,
                            isSelected: selectedVibe == vibe,
                            onTap: {
                                SpotLogger.info("User selected vibe: \(vibe)")
                                selectedVibe = vibe
                            }
                        )
                    }
                }
                .padding(.horizontal, Constants.Layout.Padding.horizontal)
                // Custom vibe (Pro)
                VStack(spacing: Constants.Layout.Spacing.small) {
                    HStack {
                        Text("Custom vibe tag")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                        Spacer()
                        Text("\(customVibe.count)/\(Constants.Limits.vibeTagMaxLength)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, Constants.Layout.Padding.horizontal)

                    HStack(spacing: Constants.Layout.Spacing.small) {
                        TextField("e.g. Golden Hour", text: $customVibe)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .foregroundColor(Constants.Colors.primary)
                            .padding(Constants.Layout.Padding.verticalMedium)
                            .background(Color.white)
                            .cornerRadius(Constants.Layout.CornerRadius.medium)
                            .overlay(RoundedRectangle(cornerRadius: Constants.Layout.CornerRadius.medium).stroke(Constants.Colors.primary, lineWidth: 1))

                        Button(action: useCustomVibe) {
                            Text("Use")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .padding(.horizontal, Constants.Layout.Padding.verticalMedium)
                                .padding(.vertical, Constants.Layout.Padding.verticalSmall)
                                .background(Constants.Colors.primary)
                                .cornerRadius(Constants.Layout.CornerRadius.small)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, Constants.Layout.Padding.horizontal)

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, Constants.Layout.Padding.horizontal)
                    }
                }
            }

            Spacer()
        }
    }

    private func useCustomVibe() {
        guard authVM.isPro else {
            NotificationCenter.default.post(name: .showPaywall, object: nil)
            return
        }
        let validator = VibeTagValidator()
        switch validator.validate(customVibe) {
        case .ok(let tag):
            validationMessage = nil
            selectedVibe = tag
            // Persist globally and on the user profile for reuse
            Task {
                await VibeTagService.shared.ensureExistsAndAttachToUser(name: tag, userId: authVM.userId)
                // Optimistic local update so it shows under "Your tags" immediately
                await MainActor.run {
                    if !authVM.customVibeTags.contains(tag) {
                        authVM.customVibeTags.append(tag)
                    }
                }
            }
        case .tooShort:
            validationMessage = Constants.ValidationMessages.vibeTooShort
        case .tooLong:
            validationMessage = Constants.ValidationMessages.vibeTooLong
        case .blocked:
            validationMessage = Constants.ValidationMessages.vibeBlocked
        }
    }
}

// MARK: - Vibe Tag Button
struct VibeTagButton: View {
    let vibe: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(vibe)
                .font(FontManager.primaryText())
                .foregroundColor(isSelected ? .white : Constants.Colors.primary)
                .padding(.horizontal, Constants.Layout.Padding.verticalLarge)
                .padding(.vertical, Constants.Layout.Padding.verticalMedium)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.CornerRadius.large)
                        .fill(isSelected ? Constants.Colors.primary : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.CornerRadius.large)
                        .stroke(Constants.Colors.primary, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VibeSelectionView(selectedVibe: .constant(""))
}
