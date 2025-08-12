import SwiftUI

struct SkeletonSpotCard: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(shimmer).frame(width: 32, height: 32)
                RoundedRectangle(cornerRadius: 6).fill(shimmer).frame(width: 120, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(shimmer).frame(width: 100, height: 14)
            }
            .padding(.horizontal, 12)

            RoundedRectangle(cornerRadius: 12)
                .fill(shimmer)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            HStack {
                RoundedRectangle(cornerRadius: 6).fill(shimmer).frame(width: 24, height: 24)
                RoundedRectangle(cornerRadius: 6).fill(shimmer).frame(width: 24, height: 24)
                Spacer()
                RoundedRectangle(cornerRadius: 10).fill(shimmer).frame(width: 80, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Constants.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
    }

    private var shimmer: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.35), Color.gray.opacity(0.25)]), startPoint: .leading, endPoint: .trailing)
    }
}


