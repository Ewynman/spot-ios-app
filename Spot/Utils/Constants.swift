//
//  Constants.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

enum Constants {

    enum Colors {
        static let background = Color(hex: "#F5F3EF")      // Main background color, button text color
        static let buttonText = Color(hex: "#F5F3EF")      // Button text color
        static let primary = Color(hex: "#1D2C24")         // Button color, icon, and main text color
        static let textPrimary = Color(hex: "#1D2C24")     // Main text color (all text except button text)
        static let accent = Color(hex: "#DEE6D8")          // Accent color for vibe tags only
    }

    enum UserDefaultsKeys {
        static let firstRun = "firstRun"
        static let notificationsRequested = "notificationsRequested"
        static let locationPermissionRequested = "locationPermissionRequested"
        static let lastKnownLocationStatus = "lastKnownLocationStatus"
        static let lastKnownNotificationStatus = "lastKnownNotificationStatus"
        static let promptPermsOnNextLogin = "promptPermsOnNextLogin"
    }

    enum Analytics {
        static let authReinstall = "AuthReinstall"
        static let permissionsRequested = "Perms.Requested"
        static let feedDropPrivate = "Feed.DropPrivate"
        static let imageLoadFailed = "Image.LoadFailed"
        static let authEmailInUse = "Auth.EmailInUse"
        static let authDeleteByEmail = "Auth.DeleteByEmail"
    }

    enum VibeTags {
        static let defaultTags: [String] = [
            "Chill Spot",
            "Hidden Gem",
            "Scenic View",
            "Romantic",
            "Great For Photos",
            "Family Friendly",
            "Nature Escape",
            "Foodie Heaven",
            "Beach Day",
            "Late Night",
            "Historical",
            "People Watching",
            "Quiet Moment",
            "Cozy Corner",
            "Pet Friendly",
            "Adventure",
            "Waterfront",
            "Study Spot"
        ]
    }

    enum Layout {
        enum Padding {
            static let horizontal: CGFloat = 32
            static let verticalSmall: CGFloat = 8
            static let verticalMedium: CGFloat = 12
            static let verticalLarge: CGFloat = 16
            static let verticalExtraLarge: CGFloat = 24
        }

        enum Spacing {
            static let small: CGFloat = 8
            static let medium: CGFloat = 12
            static let large: CGFloat = 16
            static let extraLarge: CGFloat = 24
        }

        enum CornerRadius {
            static let small: CGFloat = 10
            static let medium: CGFloat = 12
            static let large: CGFloat = 20
        }
    }

    enum ValidationMessages {
        static let vibeTooShort = "Please use at least 2 characters."
        static let vibeTooLong = "Please keep it under 30 characters."
        static let vibeBlocked = "That tag isn't allowed."
    }

    enum Limits {
        static let vibeTagMaxLength = 30
        static let vibeTagMinLength = 2
    }

    enum HTTPErrorCode {
        static let unauthorized = 401
        static let badRequest = 400
        static let internalServerError = 500
    }

    enum Pagination {
        static let defaultPageSize = 24
        static let largePageSize = 100
        static let extraLargePageSize = 200
        static let maxPageSize = 500
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
