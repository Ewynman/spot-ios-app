//
//  PreAuthTermsAgreementStore.swift
//  Spot
//
//  Tracks whether the user has acknowledged Spot's Terms of Use and Privacy
//  Policy before triggering authentication on the Welcome screen.
//
//  This is intentionally a *pre-auth* gate: we cannot write
//  `user_terms_acceptances` until the user is authenticated, so the Welcome
//  screen relies on a published flag here. The flag is reset on app launch
//  (default behavior) so each fresh app session shows the unchecked Terms
//  checkbox to App Review reviewers as required by Apple Guideline 1.2.
//
//  Once the user has authenticated successfully, `RootView` calls
//  `TermsAcceptanceService.recordAcceptance()` to persist the agreement to
//  Supabase.
//

import Foundation
import Combine

@MainActor
final class PreAuthTermsAgreementStore: ObservableObject {
    static let shared = PreAuthTermsAgreementStore()

    /// True when the user has ticked the pre-auth Terms checkbox during the
    /// current launch.  Reset every cold launch so reviewers see the unchecked
    /// state on first open.
    @Published private(set) var hasAgreed: Bool = false

    /// Source of the active Terms / Privacy URLs to render alongside the
    /// checkbox. Loaded lazily from Supabase via `TermsAcceptanceService`; the
    /// fallback uses the App Store-registered URLs in case the network call
    /// fails so the gate stays usable offline.
    @Published private(set) var activeVersion: ActiveTermsVersion?

    static let fallbackTermsURL = URL(string: "https://spotapp.online/terms")!
    static let fallbackPrivacyURL = URL(string: "https://spotapp.online/privacy")!

    private let service: TermsAcceptanceServicing

    init(service: TermsAcceptanceServicing = TermsAcceptanceService.shared) {
        self.service = service
    }

    /// User toggled the pre-auth checkbox. Logs the change so we have audit
    /// breadcrumbs in case Apple Review questions the gate behavior.
    func setAgreed(_ agreed: Bool) {
        guard hasAgreed != agreed else { return }
        hasAgreed = agreed
        SpotLogger.log(TermsAcceptanceLogs.preAuthAgreementToggled, details: [
            "hasAgreed": agreed
        ])
    }

    /// Called when the user attempted to authenticate without first agreeing.
    /// We log the gating so it's visible in support timelines.
    func logGated(action: String) {
        SpotLogger.log(TermsAcceptanceLogs.preAuthAgreementGated, details: [
            "action": action
        ])
    }

    /// Reset the agreement flag; only invoked on user sign-out / account
    /// deletion to ensure the next sign-in attempt re-presents the gate.
    func reset() {
        hasAgreed = false
        activeVersion = nil
    }

    /// Loads the active terms version from Supabase. Failures fall back to
    /// the hard-coded URLs so the Welcome screen always shows working links.
    func loadActiveVersion() async {
        do {
            let version = try await service.loadActiveVersion()
            await MainActor.run { self.activeVersion = version }
        } catch {
            // The fallback URLs handle this case; the error is already logged
            // inside TermsAcceptanceService.
        }
    }

    /// URL for the Terms of Use link. Prefers the active version row, falls
    /// back to the App Store-registered URL.
    var termsURL: URL {
        activeVersion?.termsURL ?? Self.fallbackTermsURL
    }

    /// URL for the Privacy Policy link. Prefers the active version row, falls
    /// back to the App Store-registered URL.
    var privacyURL: URL {
        activeVersion?.privacyURL ?? Self.fallbackPrivacyURL
    }
}
