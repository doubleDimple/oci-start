import Foundation

/// URLSession WebSocket client (macOS 11+). Used by native SSH / Console.
final class NativeWSClient: NSObject {
    enum State: Equatable {
        case idle
        case connecting
        case open
        case closed(String?)
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let lock = NSLock()
    private var receiveLoopActive = false

    var onState: ((State) -> Void)?
    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?

    func connect(url: URL) {
        // 静默拆掉旧连接，不要回调 .closed，避免上层刚设 isConnecting 又被清掉
        lock.lock()
        receiveLoopActive = false
        let oldTask = task
        let oldSession = session
        task = nil
        session = nil
        lock.unlock()
        oldTask?.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()

        onState?(.connecting)

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600

        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        onState?(.open)
        startReceiveLoop()
    }

    func sendText(_ text: String) {
        lock.lock()
        let t = task
        lock.unlock()
        t?.send(.string(text)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onState?(.closed(error.localizedDescription))
                }
            }
        }
    }

    func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        sendText(text)
    }

    func disconnect(reason: String?) {
        lock.lock()
        receiveLoopActive = false
        let t = task
        let s = session
        task = nil
        session = nil
        lock.unlock()
        t?.cancel(with: .goingAway, reason: nil)
        s?.invalidateAndCancel()
        onState?(.closed(reason))
    }

    private func startReceiveLoop() {
        lock.lock()
        receiveLoopActive = true
        lock.unlock()
        receiveNext()
    }

    private func receiveNext() {
        lock.lock()
        let t = task
        let active = receiveLoopActive
        lock.unlock()
        guard active, let t = t else { return }

        t.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onState?(.closed(error.localizedDescription))
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async { self.onText?(text) }
                case .data(let data):
                    DispatchQueue.main.async { self.onBinary?(data) }
                @unknown default:
                    break
                }
                self.receiveNext()
            }
        }
    }
}

// MARK: - WS URL helpers

enum NativeWSURL {
    /// `http://host:port` → `ws://host:port/path`
    static func make(baseHTTP: String, path: String) throws -> URL {
        var s = baseHTTP.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        if s.hasPrefix("https://") {
            s = "wss://" + s.dropFirst("https://".count)
        } else if s.hasPrefix("http://") {
            s = "ws://" + s.dropFirst("http://".count)
        } else if !s.hasPrefix("ws://") && !s.hasPrefix("wss://") {
            s = "ws://" + s
        }
        let p = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: s + p) else {
            throw APIError.serverMessage("无效 WebSocket 地址")
        }
        return url
    }
}
