import SwiftUI

struct VibeSelectionView: View {
    @Binding var selectedVibe: String
    
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
                                selectedVibe = vibe
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
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