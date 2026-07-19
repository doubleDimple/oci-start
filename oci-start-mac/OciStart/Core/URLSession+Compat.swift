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

    /// Download to a file (macOS 11-safe). Optional progress 0…1 on main queue.
    func compatDownload(
        for request: URLRequest,
        to destination: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            final class ProgressBox {
                var observation: NSKeyValueObservation?
            }
            let box = ProgressBox()
            let task = downloadTask(with: request) { tempURL, response, error in
                box.observation?.invalidate()
                box.observation = nil
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    cont.resume(throwing: URLError(.badServerResponse))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    cont.resume(throwing: URLError(.badServerResponse))
                    return
                }
                do {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try fm.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fm.moveItem(at: tempURL, to: destination)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
            if let progress = progress {
                box.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
                    DispatchQueue.main.async {
                        progress(prog.fractionCompleted)
                    }
                }
            }
            task.resume()
        }
    }
}
