import SwiftUI

struct SpotImageGallery: View {
    let urls: [String]
    let fallback: String?
    @State private var selection: Int = 0
    @State private var failedIndices: Set<Int> = []

    var body: some View {
        let all = orderedURLs
        TabView(selection: $selection) {
            ForEach(Array(all.enumerated()), id: \.offset) { idx, urlString in
                if let url = URL(string: urlString) {
                    RemoteImage(url: url, maxPixelSize: 1200, transaction: Transaction(animation: .default)) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Constants.Colors.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                        case .success(let image):
                            image.resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .clipped()
                                .cornerRadius(12)
                                .onAppear {
                                    failedIndices.remove(idx)
                                }
                        case .failure:
                            Image("image_placeholder")
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
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
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                        }
                    }
                    .tag(idx)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .onAppear {
            if selection >= all.count {
                selection = 0
            }
        }
    }

    private var orderedURLs: [String] {
        let base = urls.isEmpty ? (fallback.map { [$0] } ?? []) : urls
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
