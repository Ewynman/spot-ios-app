import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ConfirmEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isChecking = false
    @State private var timerActive = true
    @State private var secondsLeft: Int = 0
    @State private var showToast: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Constants.Colors.primary)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Text("Confirm your email")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)

            Text("We sent a verification email to \(authVM.maskedEmail). Open it to verify your account.")
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button { openMail() } label: {
                    Text("Open Mail")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.buttonText)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Constants.Colors.primary)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button { Task { await checkNow() } } label: {
                    Text(isChecking ? "Checking..." : "I've verified")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Constants.Colors.primary, lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isChecking)
            }

            Button {
                Task { await resend() }
            } label: {
                if authVM.canResendVerification() {
                    Text("Resend email")
                        .font(FontManager.primaryText())
                        .foregroundColor(Constants.Colors.primary)
                } else {
                    Text("Resend in \(authVM.secondsUntilResend())s")
                        .font(FontManager.primaryText())
                        .foregroundColor(.gray)
                }
            }
            .disabled(!authVM.canResendVerification())
            .buttonStyle(PlainButtonStyle())

            Spacer()
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { startAutoCheck() }
        .overlay(alignment: .top) {
            if let msg = showToast {
                ToastView(message: msg, isError: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showToast = nil } } }
            }
        }
    }

    private func openMail() { if let url = URL(string: "message://") { UIApplication.shared.open(url) } }

    private func startAutoCheck() {
        var elapsed: TimeInterval = 0
        let max: TimeInterval = 5 * 60
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in
            if !timerActive { timer.invalidate(); return }
            elapsed += 10
            Task { let ok = await authVM.checkVerificationStatus(); if ok { proceed() } }
            if elapsed >= max { SpotLogger.warning("Auth.EmailVerify.Timeout"); timer.invalidate() }
        }
    }

    private func checkNow() async {
        isChecking = true
        let ok = await authVM.checkVerificationStatus()
        isChecking = false
        if ok { proceed() }
    }

    private func resend() async {
        guard authVM.canResendVerification() else { return }
        await authVM.sendVerificationEmail()
        showToast = "Verification email sent"
        SpotLogger.info("Auth.EmailVerify.Resent")
    }

    private func proceed() {
        // Ensure user doc exists
        if let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore().collection("users").document(uid).setData(["isVerified": true], merge: true)
        }
        // Pop to root (RootView will render HomepageView when authenticated)
        dismiss()
    }
}


