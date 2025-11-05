import SwiftUI

struct CoachMarkOverlay: View {
    let targetRect: CGRect?
    let title: String
    let subtitle: String
    let isLast: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var animate: Bool = false

    var body: some View {
        ZStack {
            // Dim layer with cutout using destinationOut
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                if let rect = targetRect {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                        .animation(.easeInOut(duration: 0.25), value: targetRect)
                }
            }
            .compositingGroup()
            .accessibilityHidden(true)

            // Content
            VStack(spacing: 12) {
                Text(title)
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.buttonText)
                Text(subtitle)
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button(action: onNext) {
                        Text(isLast ? "Done" : "Next")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Constants.Colors.primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
    }
}

// Demo overlay that draws its own fake card and highlights the requested element
struct CoachDemoOverlay: View {
    let step: HomeTourManager.Step
    let title: String
    let subtitle: String
    let isLast: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            // Fake card (white body only)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(Constants.Colors.primary).frame(width: 28, height: 28)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(step == .username ? Constants.Colors.primary : Color.gray.opacity(0.3))
                            .frame(width: 120, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(step == .location ? Constants.Colors.primary : Color.gray.opacity(0.3))
                            .frame(width: 140, height: 14)
                    }
                    .padding(.horizontal, 16)

                    // Placeholder image
                    Image("tour_placeholder")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(12)

                    HStack {
                        // Like / Save placeholders
                        HStack(spacing: 16) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(step == .likeSave ? Constants.Colors.primary : Color.gray.opacity(0.3))
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(step == .likeSave ? Constants.Colors.primary : Color.gray.opacity(0.3))
                        }
                        Spacer()
                        RoundedRectangle(cornerRadius: 12)
                            .fill(step == .vibe ? Constants.Colors.primary : Color.gray.opacity(0.3))
                            .frame(width: 84, height: 24)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Text(title)
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.buttonText)
                Text(subtitle)
                    .font(FontManager.primaryText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button(action: onNext) {
                        Text(isLast ? "Done" : "Next")
                            .font(FontManager.buttonText())
                            .foregroundColor(Constants.Colors.buttonText)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Constants.Colors.primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

        }
    }

    // No-op retained for compatibility if needed
    private func highlight(_ target: HomeTourManager.Step) -> Color { step == target ? Constants.Colors.primary : Color.gray.opacity(0.3) }
}

#Preview {
    CoachMarkOverlay(
        targetRect: CGRect(x: 100, y: 200, width: 160, height: 120),
        title: "Welcome",
        subtitle: "Tap next to continue the tour.",
        isLast: false,
        onNext: {},
        onSkip: {}
    )
}
