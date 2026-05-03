//
//  LoggingSettingsDetailView.swift
//  Spot
//
//  DEBUG-only: per-area console logging toggles (non-release builds).
//

import SwiftUI

#if DEBUG
struct LoggingSettingsDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Constants.UserDefaultsKeys.debugLoggingEnabled) private var debugLoggingEnabled = true
    @AppStorage(Constants.UserDefaultsKeys.logAllDebugCategories) private var logAllDebugCategories = false
    @AppStorage(Constants.UserDefaultsKeys.logSpotCard) private var logSpotCard = false
    @AppStorage(Constants.UserDefaultsKeys.logPrivacy) private var logPrivacy = false
    @AppStorage(Constants.UserDefaultsKeys.logFeedComponent) private var logFeedComponent = false
    @AppStorage(Constants.UserDefaultsKeys.logPostFlow) private var logPostFlow = false
    @AppStorage(Constants.UserDefaultsKeys.logAuth) private var logAuth = false
    @AppStorage(Constants.UserDefaultsKeys.logNetworkComponent) private var logNetworkComponent = false
    @AppStorage(Constants.UserDefaultsKeys.logDeepLink) private var logDeepLink = false

    var body: some View {
        VStack(spacing: 0) {
            settingsTopBar(title: "Console logging", dismiss: dismiss)
            ScrollView {
                VStack(spacing: 24) {
                    settingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Global")
                            Text("Release (App Store / TestFlight) builds log errors only, regardless of these settings.")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)

                            Toggle(isOn: $debugLoggingEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Console logging")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                    Text("When off, hides debug and info in Xcode; errors still print.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Constants.Colors.primary)
                            .accessibilityIdentifier("settings.logging.masterToggle")

                            Toggle(isOn: $logAllDebugCategories) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("All debug categories")
                                        .font(FontManager.primaryText())
                                        .foregroundColor(Constants.Colors.primary)
                                    Text("Verbose: enables every debug path (ignores the area toggles below).")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Constants.Colors.primary)
                            .disabled(!debugLoggingEnabled)
                            .accessibilityIdentifier("settings.logging.allCategoriesToggle")
                        }
                    }

                    settingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Areas")
                            areaToggle("Feed", isOn: $logFeedComponent, id: "settings.logging.feed")
                            areaToggle("Upload & post flow", isOn: $logPostFlow, id: "settings.logging.postFlow")
                            areaToggle("Network & images", isOn: $logNetworkComponent, id: "settings.logging.network")
                            areaToggle("Auth", isOn: $logAuth, id: "settings.logging.auth")
                            areaToggle("Deep links", isOn: $logDeepLink, id: "settings.logging.deepLink")
                            areaToggle("Privacy / author filter", isOn: $logPrivacy, id: "settings.logging.privacy")
                            areaToggle("Spot card", isOn: $logSpotCard, id: "settings.logging.spotCard")
                        }
                    }

                    settingsSection {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Defaults file")
                            Text("Edit `Spot/Config/LoggingDefaults.plist` to change first-launch defaults for these keys.")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: "F5F3EF").ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onChange(of: debugLoggingEnabled) { _, _ in apply() }
        .onChange(of: logAllDebugCategories) { _, _ in apply() }
        .onChange(of: logSpotCard) { _, _ in apply() }
        .onChange(of: logPrivacy) { _, _ in apply() }
        .onChange(of: logFeedComponent) { _, _ in apply() }
        .onChange(of: logPostFlow) { _, _ in apply() }
        .onChange(of: logAuth) { _, _ in apply() }
        .onChange(of: logNetworkComponent) { _, _ in apply() }
        .onChange(of: logDeepLink) { _, _ in apply() }
    }

    private func apply() {
        LoggingConfig.applyFromUserDefaults()
    }

    private func areaToggle(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(FontManager.primaryText())
                .foregroundColor(Constants.Colors.primary)
        }
        .tint(Constants.Colors.primary)
        .disabled(!debugLoggingEnabled || logAllDebugCategories)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Layout (mirrors SettingsView private helpers)

private func settingsTopBar(title: String, dismiss: DismissAction) -> some View {
    HStack {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Constants.Colors.primary)
        }
        .buttonStyle(PlainButtonStyle())

        Text(title)
            .font(FontManager.sectionHeader())
            .foregroundColor(Constants.Colors.primary)
            .frame(maxWidth: .infinity)

        Spacer().frame(width: 40)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
}

private func sectionHeader(_ title: String) -> some View {
    HStack {
        Text(title)
            .font(FontManager.sectionHeader())
            .fontWeight(.semibold)
            .foregroundColor(Constants.Colors.primary)
        Spacer()
    }
}

private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        content()
    }
    .padding(16)
    .background(Color.white)
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
}
#endif
