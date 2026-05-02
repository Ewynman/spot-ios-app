//
//  ThemedAppleSignInButton.swift
//  Spot
//
//  Created by Edward Wynman on 4/20/2026.
//

import SwiftUI
import AuthenticationServices

struct ThemedAppleSignInButton: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isInFlight = false

    var onRequest: (() -> Void)? = nil
    var onSuccess: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil
    var height: CGFloat = 56

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                guard !isInFlight else { return }
                isInFlight = true
                onRequest?()
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                handleAppleResult(result)
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Constants.Colors.primary, lineWidth: 1)
        )
        .opacity(isInFlight ? 0.72 : 1)
        .allowsHitTesting(!isInFlight)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            isInFlight = false
            onError?(error.localizedDescription)
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                isInFlight = false
                onError?("Could not read Apple credential.")
                return
            }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  !idToken.isEmpty
            else {
                isInFlight = false
                onError?("Apple did not return a valid identity token.")
                return
            }

            Task {
                do {
                    try await authVM.signInWithApple(idToken: idToken, fullName: credential.fullName)
                    await MainActor.run {
                        isInFlight = false
                        onSuccess?()
                    }
                } catch {
                    await MainActor.run {
                        isInFlight = false
                        onError?(error.localizedDescription)
                    }
                }
            }
        }
    }
}
