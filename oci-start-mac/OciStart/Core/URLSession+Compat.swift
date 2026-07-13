import Foundation

/// macOS 11 / Xcode 13: URLSession async APIs require macOS 12+.
extension URLSession {
    func compatData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            dataTask(with: request) { data, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (data ?? Data(), response ?? URLResponse()))
            }.resume()
        }
    }

    func compatData(from url: URL) async throws -> (Data, URLResponse) {
        try await compatData(for: URLRequest(url: url))
    }
}
