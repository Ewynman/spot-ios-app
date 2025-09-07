//
//  SpotUnavailableView.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import SwiftUI

struct SpotUnavailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            // Title
            Text("Spot Unavailable")
                .font(FontManager.primaryText())
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            Text("This spot may have been removed, is private, or you may not have permission to view it.")
                .font(FontManager.primaryText())
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Dismiss Button
            Button(action: onDismiss) {
                Text("Go Back")
                    .font(FontManager.primaryText())
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Constants.Colors.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    SpotUnavailableView {
        print("Dismiss tapped")
    }
}
