import SwiftUI

struct SuccessToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(FontManager.primaryText())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green)
        .cornerRadius(20)
        .shadow(radius: 4)
    }
}

#Preview {
    ZStack {
        Color(hex: "F5F3EF").ignoresSafeArea()
        SuccessToastView(message: "Saved")
    }
}
