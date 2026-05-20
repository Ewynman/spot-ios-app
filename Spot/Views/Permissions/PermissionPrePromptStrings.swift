//
//  PermissionPrePromptStrings.swift
//  Spot
//
//  Single source of truth for user-facing strings on Spot’s custom screens
//  shown immediately before Apple’s system permission dialogs.
//  Centralizing them lets us:
//
//   * Verify neutral, App Review-safe wording via a regression test suite
//     (`PermissionPrePromptStringsTests`).
//   * Re-use the same text from Settings-adjacent flows and contextual
//     feature entry points (map, composer, profile, etc.).
//
//  Apple App Review (Guideline 5.1.1 / 5.1.5 / 4.5.4) requires:
//   * Primary buttons must be neutral (`Continue`, never `Enable...`).
//   * Secondary actions must let the user proceed without granting the
//     permission (e.g. `Continue Without Photos`).
//   * No `Maybe Later` immediately before the native permission prompt.
//   * Denied state must keep the app usable.
//

import Foundation

enum PermissionPrePromptStrings {
    /// Neutral primary button used to proceed to the native iOS permission
    /// prompt.
    static let continueButton = "Continue"

    /// Neutral primary button used when the user has previously denied the
    /// permission and the only remaining action is to open iOS Settings.
    static let openSettingsButton = "Open iOS Settings"

    enum Location {
        static let title = "Show nearby spots"
        static let body = "Spot can use your location to show nearby places. You can still explore the map without sharing your location."
        static let deniedBody = "Location access is off. You can still explore the map. We’ll show a United States overview instead."
        static let secondaryAction = "Continue Without Location"
    }

    enum Notifications {
        static let title = "Stay updated"
        static let body = "Spot can send notifications about activity related to your spots and saved places. Notifications are optional."
        static let deniedBody = "Notifications are off. You can still use Spot normally."
        static let secondaryAction = "Continue Without Notifications"
    }

    enum Camera {
        static let title = "Take a photo"
        static let body = "Spot uses the camera only when you choose to take a photo for your profile or a spot."
        static let deniedBody = "Camera access is off. You can still choose an existing photo or continue without a photo."
        static let secondaryAction = "Continue Without Camera"
    }

    enum Photos {
        static let title = "Choose a photo"
        static let body = "Spot uses your photo library only when you choose photos for your profile or a spot."
        static let deniedBody = "Photo library access is off. You can continue without adding photos or update access in Settings."
        static let secondaryAction = "Continue Without Photos"
    }

    /// Strings that must NEVER appear on a permission pre-prompt button or
    /// title. `PermissionPrePromptStringsTests` asserts every constant in this
    /// file stays clear of these phrases.
    static let forbiddenPhrases: [String] = [
        "Enable Location",
        "Enable Camera",
        "Enable Photos",
        "Enable Notifications",
        "Allow Location",
        "Allow Camera",
        "Allow Photos",
        "Allow Notifications",
        "Turn On Notifications",
        "Maybe Later",
        "Maybe later",
        "Must enable",
        "Required"
    ]

    /// All user-facing strings used on the four custom pre-prompts. Used
    /// by `PermissionPrePromptStringsTests` so adding a new prompt
    /// automatically gets covered by the App Review-safe assertions.
    /// Every entry is part of a contextual pre-permission screen that
    /// fires the native iOS dialog after the user taps Continue, so
    /// nothing in this list may contain a forbidden phrase
    /// (`Maybe Later`, `Allow ...`, `Enable ...`, etc.).
    static let allUserFacingStrings: [String] = [
        continueButton,
        openSettingsButton,
        Location.title, Location.body, Location.deniedBody, Location.secondaryAction,
        Notifications.title, Notifications.body, Notifications.deniedBody, Notifications.secondaryAction,
        Camera.title, Camera.body, Camera.deniedBody, Camera.secondaryAction,
        Photos.title, Photos.body, Photos.deniedBody, Photos.secondaryAction
    ]
}
