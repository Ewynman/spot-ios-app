import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Go Pro")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("$9.99 / year")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                    Divider()
                    Group {
                        FeatureRow(title: "Custom vibe tags")
                        FeatureRow(title: "Up to 5 images per spot")
                        FeatureRow(title: "Edit spots after posting")
                        FeatureRow(title: "Unlimited bookmarks")
                        FeatureRow(title: "Collections for bookmarks")
                        FeatureRow(title: "Advanced search filters")
                        FeatureRow(title: "Supporter badge")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                .padding(.horizontal, 16)

                Spacer()

                Button(action: subscribe) {
                    Text("Go Pro - $9.99 / year")
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.primary)
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 8)
            }
            .padding(.top, 16)
            .background(Constants.Colors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Constants.Colors.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func subscribe() {
        SpotLogger.info("PaywallView: User clicked subscribe, redirecting to website")
        SubscriptionWebService.shared.openSubscriptionPageForCurrentUser()
        dismiss()
    }
}

#Preview {
    let auth = AuthViewModel()
    return PaywallView().environmentObject(auth)
}

private struct FeatureRow: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Constants.Colors.primary)
            Text(title).font(FontManager.primaryText()).foregroundColor(Constants.Colors.primary)
        }
    }
}
