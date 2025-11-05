import SwiftUI
import FirebaseAuth

struct ConfirmNewEmailView: View {
    let newEmail: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isChecking = false
    @State private var showToast: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left"); Text("Back")
                    }.foregroundColor(Constants.Colors.primary)
                }.buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)

            Text("Confirm new email")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)

            Text("Check \(newEmail) for a verification link. Your email will update after you verify.")
                .font(FontManager.primaryText()).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button { openMail() } label: {
                    Text("Open Mail").font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Constants.Colors.primary).cornerRadius(12)
                }.buttonStyle(PlainButtonStyle())

                Button { Task { await checkNow() } } label: {
                    Text(isChecking ? "Checking..." : "I've verified")
                        .font(FontManager.primaryText()).foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                }.buttonStyle(PlainButtonStyle()).disabled(isChecking)
            }

            Button { Task { await resend() } } label: {
                if authVM.canResendVerification() {
                    Text("Resend email").font(FontManager.primaryText()).foregroundColor(Constants.Colors.primary)
                } else {
                    Text("Resend in \(authVM.secondsUntilResend())s").font(FontManager.primaryText()).foregroundColor(.gray)
                }
            }
            .disabled(!authVM.canResendVerification()).buttonStyle(PlainButtonStyle())

            Spacer()
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .top) {
            if let msg = showToast {
                ToastView(message: msg, isError: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showToast = nil } } }
            }
        }
    }

    private func openMail() { if let url = URL(string: "message://") { UIApplication.shared.open(url) } }

    private func checkNow() async {
        isChecking = true
        defer { isChecking = false }
        do {
            try await Auth.auth().currentUser?.reload()
            if let user = Auth.auth().currentUser, let email = user.email, email.lowercased() == newEmail.lowercased() {
                SpotLogger.info("Auth.ChangeEmail.Verified")
                dismiss()
            }
        } catch { SpotLogger.error("checkNow failed: \(error.localizedDescription)") }
    }

    private func resend() async {
        guard authVM.canResendVerification() else { return }
        do {
            try await Auth.auth().currentUser?.sendEmailVerification(beforeUpdatingEmail: newEmail)
            SpotLogger.info("Auth.ChangeEmail.VerifySent")
            await MainActor.run { authVM.emailResendAvailableAt = Date().addingTimeInterval(30) }
            showToast = "Verification email sent"
        } catch {
            SpotLogger.error("resend failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    let auth = AuthViewModel()
    return ConfirmNewEmailView(newEmail: "new@example.com").environmentObject(auth)
}
