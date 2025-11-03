import SwiftUI

struct SpotImageGallery: View {
    let urls: [String]
    let fallback: String?
    @State private var selection: Int = 0

    var body: some View {
        let all = urls.isEmpty ? (fallback.map { [$0] } ?? []) : urls
        TabView(selection: $selection) {
            ForEach(Array(all.enumerated()), id: \.offset) { idx, urlString in
                if let url = URL(string: urlString) {
                    AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
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
                        case .failure:
                            Image("image_placeholder")
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .clipped()
                                .cornerRadius(12)
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
    }
}
