import SwiftUI

struct ConfirmEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var otpDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var showToast: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    authVM.clearEmailVerificationPending()
                    dismiss()
                } label: {
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

            Text("Enter verification code")
                .font(FontManager.sectionHeader())
                .foregroundColor(Constants.Colors.primary)

            Text("We sent a 6-digit code to \(authVM.maskedEmail). Enter it below to confirm your account.")
                .font(FontManager.primaryText())
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: Binding(
                        get: { otpDigits[index] },
                        set: { newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered.count <= 1 {
                                otpDigits[index] = String(filtered.prefix(1))
                            } else {
                                let chars = Array(filtered.prefix(6))
                                for i in 0..<min(chars.count, 6) {
                                    otpDigits[i] = String(chars[i])
                                }
                            }
                            if !newValue.isEmpty, index < 5 {
                                focusedIndex = index + 1
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(index == 0 ? .oneTimeCode : nil)
                    .multilineTextAlignment(.center)
                    .font(FontManager.sectionHeader())
                    .foregroundColor(Constants.Colors.primary)
                    .tint(Constants.Colors.primary)
                    .frame(width: 44, height: 52)
                    .background(Constants.Colors.background)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Constants.Colors.primary, lineWidth: 1))
                    .focused($focusedIndex, equals: index)
                    .onChange(of: otpDigits[index]) { oldValue, newValue in
                        if newValue.isEmpty && !oldValue.isEmpty && index > 0 {
                            focusedIndex = index - 1
                        }
                    }
                }
            }
            .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(FontManager.primaryText())
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await verifyTapped() }
            } label: {
                Text(isVerifying ? "Verifying..." : "Verify")
                    .font(FontManager.buttonText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Constants.Colors.primary)
                    .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isVerifying || otpCode.count != 6)
            .padding(.horizontal, 32)
            .padding(.top, 8)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Button {
                    Task { await resend() }
                } label: {
                    if authVM.canResendVerification() {
                        Text(isResending ? "Sending..." : "Resend code")
                            .font(FontManager.primaryText())
                            .foregroundColor(Constants.Colors.primary)
                    } else {
                        Text("Resend in \(authVM.secondsUntilResend())s")
                            .font(FontManager.primaryText())
                            .foregroundColor(.gray)
                    }
                }
                .disabled(!authVM.canResendVerification() || isResending)
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear { focusedIndex = 0 }
        .overlay(alignment: .top) {
            if let msg = showToast {
                ToastView(message: msg, isError: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showToast = nil } } }
            }
        }
    }

    private var otpCode: String {
        otpDigits.joined()
    }

    private func verifyTapped() async {
        errorMessage = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await authVM.verifySignupEmailOTP(code: otpCode)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resend() async {
        guard authVM.canResendVerification() else { return }
        isResending = true
        defer { isResending = false }
        errorMessage = nil
        do {
            try await authVM.sendVerificationEmail()
            showToast = "Code sent"
            SpotLogger.log(ConfirmEmailViewLogs.verificationEmailResent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let auth = AuthViewModel()
    auth.beginEmailVerificationPending(email: "hello@example.com", avatar: nil)
    return ConfirmEmailView().environmentObject(auth)
}
