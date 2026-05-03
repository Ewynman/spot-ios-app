import SwiftUI

struct SpotImageGallery: View {
    let urls: [String]
    let fallback: String?
    /// Optional: when set, allows the gallery to lazily fetch the full image
    /// array for this spot the first time the user pages past the primary
    /// image. Used by the v2 home feed where each row only carries its primary.
    var spotId: String? = nil
    @State private var selection: Int = 0
    @State private var failedIndices: Set<Int> = []
    @State private var lazilyLoaded: [String] = []
    @State private var didRequestFullSet = false

    var body: some View {
        let all = orderedURLs
        /// Page `TabView` + loaded `Image` intrinsic sizes can widen scroll content
        /// unless each page uses an explicit width from the parent slot.
        GeometryReader { geo in
            let slotWidth = max(geo.size.width, 1)
            TabView(selection: $selection) {
                ForEach(Array(all.enumerated()), id: \.offset) { idx, urlString in
                    if let url = URL(string: urlString) {
                        RemoteImage(url: url, maxPixelSize: 1200, transaction: Transaction(animation: .default)) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Constants.Colors.background)
                                    .frame(width: slotWidth, height: 320)
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                                    .frame(width: slotWidth, height: 320)
                                    .clipped()
                                    .cornerRadius(12)
                                    .onAppear {
                                        failedIndices.remove(idx)
                                    }
                            case .failure:
                                Image("image_placeholder")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: slotWidth, height: 320)
                                    .clipped()
                                    .cornerRadius(12)
                                    .onAppear {
                                        failedIndices.insert(idx)
                                        if selection == idx, let next = firstRenderableIndex(excluding: failedIndices, count: all.count) {
                                            selection = next
                                        }
                                    }
                            @unknown default:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Constants.Colors.background)
                                    .frame(width: slotWidth, height: 320)
                            }
                        }
                        .tag(idx)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipped()
        .onAppear {
            if selection >= all.count {
                selection = 0
            }
            requestFullSetIfNeeded()
        }
        .onChange(of: selection) { _, newValue in
            // Trigger lazy hydration the moment the user actually pages.
            if newValue > 0 { requestFullSetIfNeeded() }
        }
    }

    private var orderedURLs: [String] {
        let combined = urls + lazilyLoaded
        let base = combined.isEmpty ? (fallback.map { [$0] } ?? []) : combined
        var seen = Set<String>()
        let unique = base.filter { seen.insert($0).inserted }
        let sorted = unique.sorted { lhs, rhs in
            let leftBad = isLikelyPlaceholderURL(lhs)
            let rightBad = isLikelyPlaceholderURL(rhs)
            if leftBad == rightBad { return lhs < rhs }
            return !leftBad && rightBad
        }
        return sorted
    }

    /// On the v2 home feed each row carries only its primary image. The first
    /// time the user opens or pages this gallery, fetch the full array.
    private func requestFullSetIfNeeded() {
        guard !didRequestFullSet else { return }
        guard let spotId, let uuid = UUID(uuidString: spotId) else { return }
        // Heuristic: if we already have multiple unique URLs, the caller has
        // already provided the full set and we don't need to fetch.
        if Set(urls).count > 1 { return }
        didRequestFullSet = true
        Task {
            let all = await FeedAPI.fetchAllImageURLs(for: uuid)
            await MainActor.run {
                let extra = all.filter { !urls.contains($0) }
                if !extra.isEmpty {
                    lazilyLoaded = extra
                }
            }
        }
    }

    private func isLikelyPlaceholderURL(_ raw: String) -> Bool {
        let s = raw.lowercased()
        return s.contains("placeholder") || s.contains("default") || s.contains("image_placeholder")
    }

    private func firstRenderableIndex(excluding excluded: Set<Int>, count: Int) -> Int? {
        for idx in 0..<count where !excluded.contains(idx) { return idx }
        return nil
    }
}

#Preview {
    SpotImageGallery(
        urls: [
            "https://picsum.photos/seed/a/800/600",
            "https://picsum.photos/seed/b/800/600"
        ],
        fallback: nil
    )
    .padding()
    .background(Color(hex: "F5F3EF"))
}
