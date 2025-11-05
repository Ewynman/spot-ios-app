//
//  CustomBackButton.swift
//  Spot
//
//  Created by Edward Wynman on 7/16/25.
//

import SwiftUI

struct CustomBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Constants.Colors.primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CustomBackButton(action: {})
        .padding()
        .background(Color(hex: "F5F3EF"))
}
