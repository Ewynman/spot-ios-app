import SwiftUI

struct VibeSelectionView: View {
    @Binding var selectedVibe: String
    @EnvironmentObject var authVM: AuthViewModel
    @State private var customVibe: String = ""
    @State private var validationMessage: String?

    private let vibeTags = [
        "Chill Spot",
        "Hidden Gem",
        "Scenic View",
        "Romantic",
        "Great For Photos",
        "Family Friendly",
        "Nature Escape",
        "Foodie Heaven",
        "Beach Day",
        "Late Night",
        "Historical",
        "People Watching",
        "Quiet Moment",
        "Cozy Corner",
        "Pet Friendly",
        "Adventure",
        "Waterfront",
        "Study Spot"
    ]

    var body: some View {
        VStack(spacing: 24) {
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
            .padding(.horizontal, 32)

            // Vibe Tags Grid
            ScrollView {
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
                .padding(.horizontal, 32)
                // Custom vibe (Pro)
                VStack(spacing: 8) {
                    HStack {
                        Text("Custom vibe tag")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                        Spacer()
                        Text("\(customVibe.count)/30")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 32)

                    HStack(spacing: 8) {
                        TextField("e.g. Golden Hour", text: $customVibe)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))

                        Button(action: useCustomVibe) {
                            Text("Use")
                                .font(FontManager.primaryText())
                                .foregroundColor(Constants.Colors.buttonText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Constants.Colors.primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32)

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 32)
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
        case .tooShort:
            validationMessage = "Please use at least 2 characters."
        case .tooLong:
            validationMessage = "Please keep it under 30 characters."
        case .blocked:
            validationMessage = "That tag isn’t allowed."
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Constants.Colors.primary : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Constants.Colors.primary, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VibeSelectionView(selectedVibe: .constant(""))
}
