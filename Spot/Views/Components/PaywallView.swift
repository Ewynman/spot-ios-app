import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var priceLine = "$9.99 / year"
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Go Pro")
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)

                VStack(alignment: .leading, spacing: 12) {
                    Text(priceLine)
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
                    Text(subscriptionManager.isPurchasing ? "Processing…" : "Go Pro - \(priceLine)")
                        .font(FontManager.buttonText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.primary)
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(subscriptionManager.isPurchasing)
                .padding(.bottom, 4)

                Button("Restore purchases") {
                    restorePurchases()
                }
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
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
            .task { await loadStorePrice() }
            .alert("Purchase", isPresented: Binding(
                get: { purchaseError != nil },
                set: { if !$0 { purchaseError = nil } }
            )) {
                Button("OK", role: .cancel) { purchaseError = nil }
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    private func loadStorePrice() async {
        await subscriptionManager.ensureProductLoaded()
        guard subscriptionManager.hasProduct else { return }
        guard let product = try? await subscriptionManager.loadProduct() else { return }
        await MainActor.run {
            priceLine = "\(product.displayPrice) / year"
        }
    }

    private func subscribe() {
        purchaseError = nil
        SpotLogger.info("PaywallView: User started App Store purchase")
        Task {
            do {
                let outcome = try await subscriptionManager.purchasePro()
                switch outcome {
                case .purchased:
                    if await subscriptionManager.refreshEntitlement() {
                        await authVM.setProActive(true)
                    }
                    await MainActor.run { dismiss() }
                case .pending:
                    SpotLogger.info("PaywallView: Purchase pending")
                case .userCancelled:
                    break
                }
            } catch {
                SpotLogger.error("PaywallView: Purchase failed", details: ["error": error.localizedDescription])
                await MainActor.run { purchaseError = error.localizedDescription }
            }
        }
    }

    private func restorePurchases() {
        purchaseError = nil
        Task {
            do {
                try await subscriptionManager.restorePurchases()
                if await subscriptionManager.refreshEntitlement() {
                    await authVM.setProActive(true)
                    await MainActor.run { dismiss() }
                } else {
                    await MainActor.run { purchaseError = "No active subscription found." }
                }
            } catch {
                SpotLogger.error("PaywallView: Restore failed", details: ["error": error.localizedDescription])
                await MainActor.run { purchaseError = error.localizedDescription }
            }
        }
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
