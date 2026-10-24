import Foundation

/// Injectable transport contract shared by the native AI, SSH and console flows.
protocol NativeWSConnection: AnyObject {
    var onState: ((NativeWSClient.State) -> Void)? { get set }
    var onText: ((String) -> Void)? { get set }
    var onBinary: ((Data) -> Void)? { get set }
    func connect(url: URL)
    func sendJSON(_ object: [String: Any])
    func disconnect(reason: String?)
}

/// URLSession WebSocket client (macOS 11+). Callbacks are delivered on main.
final class NativeWSClient: NSObject, NativeWSConnection {
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
    private var generation: UInt64 = 0

    var onState: ((State) -> Void)?
    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?

    func connect(url: URL) {
        // Replacing a connection is silent. A queued old close must not change
        // the state of a new connection, including before its task is assigned.
        lock.lock()
        generation &+= 1
        let currentGeneration = generation
        receiveLoopActive = false
        let oldTask = task
        let oldSession = session
        task = nil
        session = nil
        lock.unlock()
        oldTask?.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600

        // URLSession retains its delegate until invalidation; the delegate must
        // not retain this client, which owns the URLSession.
        let delegate = NativeWSDelegate(owner: self)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        let httpURL = url.absoluteString.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
        if let cookie = APIClient.shared.cookieHeader(for: httpURL), !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let task = session.webSocketTask(with: request)
        lock.lock()
        guard generation == currentGeneration else {
            lock.unlock()
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            return
        }
        self.session = session
        self.task = task
        lock.unlock()
        notifyState(.connecting, generation: currentGeneration)
        // A synchronous main-thread state observer may already have cancelled.
        if isCurrent(task) { task.resume() }
    }

    func sendText(_ text: String) {
        lock.lock()
        let candidate = task
        lock.unlock()
        guard let candidate = candidate else { return }
        candidate.send(.string(text)) { [weak self] error in
            if let error = error {
                self?.finish(candidate, reason: self?.closureReason(candidate, error: error))
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
        generation &+= 1
        let currentGeneration = generation
        receiveLoopActive = false
        let candidate = task
        let activeSession = session
        task = nil
        session = nil
        lock.unlock()
        candidate?.cancel(with: .goingAway, reason: nil)
        activeSession?.invalidateAndCancel()
        notifyState(.closed(reason), generation: currentGeneration)
    }

    fileprivate func didOpen(_ candidate: URLSessionWebSocketTask) {
        onMain { owner in
            owner.lock.lock()
            guard owner.task === candidate, !owner.receiveLoopActive else {
                owner.lock.unlock()
                return
            }
            owner.receiveLoopActive = true
            let currentGeneration = owner.generation
            owner.lock.unlock()
            // This is the sole .open producer: URLSession confirmed the actual
            // WebSocket handshake. resume() alone is only a connection attempt.
            owner.notifyState(.open, generation: currentGeneration)
            if owner.isCurrent(candidate) { owner.receiveNext(candidate) }
        }
    }

    fileprivate func didClose(_ candidate: URLSessionWebSocketTask, reason: Data?) {
        finish(candidate, reason: reason.flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 })
    }

    fileprivate func didComplete(_ candidate: URLSessionWebSocketTask, error: Error?) {
        finish(candidate, reason: closureReason(candidate, error: error))
    }

    private func receiveNext(_ candidate: URLSessionWebSocketTask) {
        lock.lock()
        let active = receiveLoopActive && task === candidate
        lock.unlock()
        guard active else { return }
        candidate.receive { [weak self] result in
            self?.onMain { owner in
                guard owner.isCurrent(candidate) else { return }
                switch result {
                case .failure(let error):
                    owner.finish(candidate, reason: owner.closureReason(candidate, error: error))
                case .success(let message):
                    switch message {
                    case .string(let text): owner.onText?(text)
                    case .data(let data): owner.onBinary?(data)
                    @unknown default: break
                    }
                    if owner.isCurrent(candidate) { owner.receiveNext(candidate) }
                }
            }
        }
    }

    private func isCurrent(_ candidate: URLSessionWebSocketTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return task === candidate
    }

    private func closureReason(_ candidate: URLSessionWebSocketTask, error: Error?) -> String? {
        if let data = candidate.closeReason, let reason = String(data: data, encoding: .utf8), !reason.isEmpty {
            return reason
        }
        // A receive completion may race the delegate's clean-close callback.
        if candidate.closeCode == .normalClosure { return nil }
        return error?.localizedDescription
    }

    private func finish(_ candidate: URLSessionWebSocketTask, reason: String?) {
        onMain { owner in
            owner.lock.lock()
            guard owner.task === candidate else { owner.lock.unlock(); return }
            let currentGeneration = owner.generation
            let activeSession = owner.session
            owner.receiveLoopActive = false
            owner.task = nil
            owner.session = nil
            owner.lock.unlock()
            candidate.cancel(with: .goingAway, reason: nil)
            activeSession?.invalidateAndCancel()
            // Detachment above makes receive/send/delegate close races notify
            // once, and prevents stale failures from closing a replacement task.
            owner.notifyState(.closed(reason), generation: currentGeneration)
        }
    }

    private func notifyState(_ state: State, generation expected: UInt64) {
        onMain { owner in
            owner.lock.lock()
            let current = owner.generation == expected
            owner.lock.unlock()
            if current { owner.onState?(state) }
        }
    }

    private func onMain(_ operation: @escaping (NativeWSClient) -> Void) {
        if Thread.isMainThread { operation(self) }
        else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                operation(self)
            }
        }
    }

    deinit {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
}

private final class NativeWSDelegate: NSObject, URLSessionWebSocketDelegate {
    weak var owner: NativeWSClient?

    init(owner: NativeWSClient) { self.owner = owner }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        owner?.didOpen(webSocketTask)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        owner?.didClose(webSocketTask, reason: reason)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let socket = task as? URLSessionWebSocketTask else { return }
        owner?.didComplete(socket, error: error)
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
