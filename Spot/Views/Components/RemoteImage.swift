import SwiftUI
import UIKit

struct RemoteImageFailure: Error {
    let url: URL
    let statusCode: Int?
    let underlying: Error
    let mimeType: String?
    let bodyPreview: String?

    var nsError: NSError { underlying as NSError }
}

enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure(RemoteImageFailure)
}

/// A lightweight async image loader that exposes HTTP status code (via `HTTPURLResponse`) on failures.
/// This is useful for debugging Firebase Storage URL issues where `AsyncImage` does not provide the status code.
struct RemoteImage<Content: View>: View {
    private let url: URL
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase = .empty

    init(
        url: URL,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(animation: .default),
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    private func setPhase(_ newPhase: RemoteImagePhase) {
        withTransaction(transaction) {
            phase = newPhase
        }
    }

    private func load() async {
        await MainActor.run { setPhase(.empty) }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode

            if let status, !(200...299).contains(status) {
                throw makeFailure(
                    statusCode: status,
                    underlying: NSError(domain: "RemoteImage", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP status \(status)"]),
                    mimeType: http?.mimeType,
                    data: data
                )
            }

            guard let ui = UIImage(data: data, scale: scale) else {
                throw makeFailure(
                    statusCode: status,
                    underlying: NSError(domain: "RemoteImage", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"]),
                    mimeType: http?.mimeType,
                    data: data
                )
            }

            await MainActor.run { setPhase(.success(Image(uiImage: ui))) }
        } catch {
            // Best-effort to recover status code if error is our typed failure
            if let typed = error as? RemoteImageFailure {
                await MainActor.run { setPhase(.failure(typed)) }
                return
            }
            await MainActor.run {
                setPhase(.failure(RemoteImageFailure(
                    url: url,
                    statusCode: nil,
                    underlying: error,
                    mimeType: nil,
                    bodyPreview: nil
                )))
            }
        }
    }

    private func makeFailure(statusCode: Int?, underlying: Error, mimeType: String?, data: Data) -> RemoteImageFailure {
        var preview: String? = nil
        if !data.isEmpty {
            // Firebase error bodies are usually JSON; keep a short prefix to avoid huge logs.
            preview = String(data: data.prefix(512), encoding: .utf8)
        }
        return RemoteImageFailure(
            url: url,
            statusCode: statusCode,
            underlying: underlying,
            mimeType: mimeType,
            bodyPreview: preview
        )
    }
}

