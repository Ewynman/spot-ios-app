//
//  Constants.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

enum Constants {
    
    enum Colors {
        static let primary = Color(hex: "#26852B")
        static let primaryDark = Color(hex: "#1E6E23")
        static let primaryLight = Color(hex: "#E0EADC")
        static let secondary = Color(hex: "#4478B6")
        static let secondaryLight = Color(hex: "#E1E4F0")
        static let textPrimary = Color(hex: "#1A1A1A")
        static let background = Color(hex: "#F5F3EF")
    }

    enum Fonts {
        static func title() -> Font {
            .custom("SFProRounded-Bold", size: 40)
        }

        static func body() -> Font {
            .custom("SFProRounded-Regular", size: 16)
        }

        static func small() -> Font {
            .custom("SFProRounded-Regular", size: 14)
        }
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
