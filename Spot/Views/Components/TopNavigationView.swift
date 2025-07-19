import SwiftUI

struct TopNavigationView: View {
    let title: String
    let showBackButton: Bool
    let rightButton: RightButtonType
    @Binding var showUploadView: Bool
    @Environment(\.dismiss) private var dismiss
    
    enum RightButtonType {
        case none
        case settings
        case plus
    }
    
    init(
        title: String,
        showBackButton: Bool = false,
        rightButton: RightButtonType = .none,
        showUploadView: Binding<Bool> = .constant(false)
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.rightButton = rightButton
        self._showUploadView = showUploadView
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                if showBackButton {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Constants.Colors.primary)
                    }
                }
                
                Text(title)
                    .font(FontManager.logoTitle())
                    .foregroundColor(Constants.Colors.primary)
                
                Spacer()
                
                switch rightButton {
                case .settings:
                    Button(action: {
                        // Handle settings tap
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(Constants.Colors.primary)
                    }
                case .plus:
                    Button(action: {
                        SpotLogger.info("User tapped + button to start post flow")
                        showUploadView = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Constants.Colors.primary)
                            .clipShape(Circle())
                    }
                case .none:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .background(Color(hex: "F5F3EF"))
    }
}

// MARK: - Previews
struct TopNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Homepage Style
            TopNavigationView(
                title: "SPOT",
                rightButton: .plus,
                showUploadView: .constant(false)
            )
            .previewDisplayName("Homepage")
            
            // With Back Button
            TopNavigationView(
                title: "Profile",
                showBackButton: true
            )
            .previewDisplayName("With Back")
            
            // With Settings
            TopNavigationView(
                title: "Profile",
                rightButton: .settings
            )
            .previewDisplayName("With Settings")
            
            // Basic
            TopNavigationView(
                title: "Profile"
            )
            .previewDisplayName("Basic")
        }
        .previewLayout(.sizeThatFits)
    }
} 