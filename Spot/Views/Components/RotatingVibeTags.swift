//
//  RotatingVibeTags.swift
//  Spot
//

import SwiftUI
import UIKit

/// Single-row vibe display: one pill at a time with optional fade rotation when multiple labels.
struct RotatingVibeTags: View {
    let labels: [String]
    var intervalMs: Double = 2200
    var fadeDuration: Double = 0.25
    /// Show trailing "+N" when more than one label exists.
    var showPlusCount: Bool = true
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var opacity: Double = 1
    @State private var rotationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if labels.isEmpty {
                EmptyView()
            } else if labels.count == 1 {
                pill(labels[0])
            } else if reduceMotion {
                reducedMotionStack
            } else {
                rotatingStack
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityPhrase))
        .onDisappear { rotationTask?.cancel(); rotationTask = nil }
    }

    private var accessibilityPhrase: String {
        "Vibes: \(labels.joined(separator: ", "))"
    }

    /// With Reduce Motion on, the "+N" suffix must sit **outside** the `Button` label; otherwise SwiftUI
    /// button label styling can render it as a low-contrast / light tint on the cream card background.
    private var reducedMotionStack: some View {
        HStack(spacing: 2) {
            pillLabel(labels[0])
            if showPlusCount, labels.count > 1 {
                plusMoreVibesSuffix
            }
        }
        .frame(minWidth: rotatingRowMinWidth, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private var rotatingStack: some View {
        HStack(alignment: .center, spacing: 2) {
            pill(labels[index])
                .opacity(opacity)
                .accessibilityHidden(true)

            if showPlusCount, labels.count > 1 {
                plusMoreVibesSuffix
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: rotatingRowMinWidth, alignment: .trailing)
        .onAppear {
            startRotationIfNeeded()
        }
        .onChange(of: labels) { _, _ in
            index = 0
            opacity = 1
            rotationTask?.cancel()
            startRotationIfNeeded()
        }
    }

    /// Reserve width for longest label to reduce layout shift (approximate using font).
    private var measuredMinWidth: CGFloat? {
        guard labels.count > 1 else { return nil }
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let maxW = labels.map { label in
            (label as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return maxW + 28
    }

    /// Width of the "+N" suffix (caption semibold) for stable rotating-row layout.
    private var plusSuffixLayoutWidth: CGFloat {
        let text = "+\(max(0, labels.count - 1))"
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Pill column (widest vibe) + tight gap + suffix so "+N" sits flush beside the pill, not after an empty slot.
    private var rotatingRowMinWidth: CGFloat? {
        guard labels.count > 1 else { return nil }
        let pillSlot = measuredMinWidth ?? 0
        let gap: CGFloat = 2
        let suffix = showPlusCount ? plusSuffixLayoutWidth : 0
        return pillSlot + gap + suffix
    }

    private var plusMoreVibesSuffix: some View {
        Text("+\(labels.count - 1)")
            .font(.caption)
            .fontWeight(.semibold)
            // Primary green; both APIs resist inherited button/tint styling that reads as white on cream.
            .foregroundColor(Constants.Colors.primary)
            .foregroundStyle(Constants.Colors.primary)
    }

    private func pill(_ text: String) -> some View {
        Group {
            if let onTap {
                Button {
                    onTap()
                } label: {
                    pillLabel(text)
                }
                .buttonStyle(.plain)
            } else {
                pillLabel(text)
            }
        }
    }

    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(FontManager.primaryText())
            .foregroundColor(Constants.Colors.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Constants.Colors.accent)
            .cornerRadius(12)
    }

    private func startRotationIfNeeded() {
        guard labels.count > 1, !reduceMotion else { return }
        rotationTask?.cancel()
        rotationTask = Task { @MainActor in
            let nanos = UInt64(intervalMs * 1_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await fadeToNext()
            }
        }
    }

    private func fadeToNext() async {
        guard labels.count > 1 else { return }
        withAnimation(.easeOut(duration: fadeDuration)) {
            opacity = 0
        }
        try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
        index = (index + 1) % labels.count
        withAnimation(.easeIn(duration: fadeDuration)) {
            opacity = 1
        }
    }
}

#if DEBUG
#Preview("Rotate") {
    RotatingVibeTags(labels: ["Cozy", "Chaotic", "Romantic"], onTap: {})
        .padding()
}
#endif
