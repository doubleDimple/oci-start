import Foundation

/// macOS 11-compatible SSE reader (URLSessionDataDelegate chunk parse).
final class TenantSSEClient: NSObject, URLSessionDataDelegate {
    static let shared = TenantSSEClient()

    private var session: URLSession!
    private var buffer = Data()
    private var onEvent: ((String, String) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var currentEvent = "message"
    private var dataLines: [String] = []

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 600
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func stream(request: URLRequest, onEvent: @escaping (String, String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.onEvent = onEvent
            self.buffer = Data()
            self.finished = false
            self.currentEvent = "message"
            self.dataLines = []
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r")) ?? ""
            handle(line: line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        if let error = error {
            continuation?.resume(throwing: APIError.network(error))
        } else {
            flushEvent()
            continuation?.resume()
        }
        continuation = nil
        onEvent = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                finished = true
                continuation?.resume(throwing: APIError.unauthorized)
                continuation = nil
                completionHandler(.cancel)
                return
            }
            if !(200..<300).contains(http.statusCode) {
                finished = true
                continuation?.resume(throwing: APIError.serverMessage("HTTP \(http.statusCode)"))
                continuation = nil
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }

    private func handle(line: String) {
        if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        } else if line.isEmpty {
            flushEvent()
        }
    }

    private func flushEvent() {
        guard !dataLines.isEmpty else { return }
        let data = dataLines.joined(separator: "\n")
        let event = currentEvent
        dataLines = []
        currentEvent = "message"
        onEvent?(event, data)
        if event == "success" || event == "complete" || event == "error" {
            if !finished {
                finished = true
                continuation?.resume()
                continuation = nil
            }
        }
    }
}
