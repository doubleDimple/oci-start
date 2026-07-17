import Foundation

/// Cancellable continuous SSE reader for `/system/streamLogs` (macOS 11 safe).
/// Unlike `TenantSSEClient` (one-shot until complete), this stream stays open until `stop()`.
final class OpenLogsSSEClient: NSObject, URLSessionDataDelegate {
    static let shared = OpenLogsSSEClient()

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var onLine: ((String) -> Void)?
    private var onOpen: (() -> Void)?
    private var onClose: ((Error?) -> Void)?
    private var opened = false
    private var stopped = true
    private var currentEvent = "message"
    private var dataLines: [String] = []

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        // Long-lived log tail — no resource timeout; request timeout handled by server idle.
        cfg.timeoutIntervalForRequest = 0
        cfg.timeoutIntervalForResource = 0
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    /// Start (or restart) streaming. Previous connection is cancelled first.
    func start(
        request: URLRequest,
        onOpen: @escaping () -> Void,
        onLine: @escaping (String) -> Void,
        onClose: @escaping (Error?) -> Void
    ) {
        stop(notify: false)
        self.onOpen = onOpen
        self.onLine = onLine
        self.onClose = onClose
        buffer = Data()
        opened = false
        stopped = false
        currentEvent = "message"
        dataLines = []
        var req = request
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 0
        let t = session.dataTask(with: req)
        task = t
        t.resume()
    }

    func stop(notify: Bool = true) {
        let wasActive = !stopped
        stopped = true
        task?.cancel()
        task = nil
        buffer = Data()
        dataLines = []
        if notify, wasActive {
            let cb = onClose
            onOpen = nil
            onLine = nil
            onClose = nil
            cb?(nil)
        } else {
            onOpen = nil
            onLine = nil
            onClose = nil
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if stopped {
            completionHandler(.cancel)
            return
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                finish(error: APIError.unauthorized)
                completionHandler(.cancel)
                return
            }
            if !(200..<300).contains(http.statusCode) {
                finish(error: APIError.serverMessage("HTTP \(http.statusCode)"))
                completionHandler(.cancel)
                return
            }
        }
        if !opened {
            opened = true
            onOpen?()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !stopped else { return }
        if !opened {
            opened = true
            onOpen?()
        }
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
        guard !stopped else { return }
        flushEvent()
        if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            finish(error: nil)
            return
        }
        finish(error: error.map { APIError.network($0) })
    }

    // MARK: - Parse

    private func handle(line: String) {
        // SSE comment (e.g. `: ok`) — ignore, used only to flush headers
        if line.hasPrefix(":") { return }
        if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        } else if line.isEmpty {
            flushEvent()
        }
    }

    private func flushEvent() {
        guard !dataLines.isEmpty else {
            currentEvent = "message"
            return
        }
        let data = dataLines.joined(separator: "\n")
        dataLines = []
        currentEvent = "message"
        guard !data.isEmpty else { return }
        onLine?(data)
    }

    private func finish(error: Error?) {
        guard !stopped else { return }
        stopped = true
        task = nil
        let cb = onClose
        onOpen = nil
        onLine = nil
        onClose = nil
        cb?(error)
    }
}
