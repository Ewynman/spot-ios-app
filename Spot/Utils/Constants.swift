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
