import Foundation
import SwiftUI

final class ImageService {
    static let shared = ImageService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        return URLSession(configuration: config)
    }()

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        let task = session.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { completion(nil); return }
            completion(img)
        }
        task.resume()
        return task
    }
}


