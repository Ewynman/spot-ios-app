//
//  SpotLoadingView.swift
//  Spot
//
//  Created by Edward Wynman on 1/27/25.
//

import SwiftUI

struct SpotLoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Loading indicator
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Constants.Colors.primary))
            
            // Loading text
            Text("Loading Spot...")
                .font(FontManager.primaryText())
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    SpotLoadingView()
}
