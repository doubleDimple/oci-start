import Foundation
import Combine
import AppKit

/// ViewModel for Web `/system/logs` — history + live SSE tail (isBootLog=false).
@MainActor
final class SystemLogsViewModel: ObservableObject {

    static let maxLines = 1000

    @Published private(set) var entries: [OpenLogEntry] = []
    @Published private(set) var connection: OpenLogsConnectionState = .disconnected
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var errorText: String?
    @Published var autoScroll = true
    @Published private(set) var clockText: String = ""
    @Published private(set) var scrollToken: Int = 0

    private let session: AppSession
    private var service: SystemLogsService { SystemLogsService(baseURL: session.serverURL) }
    private var nextId = 1
    private var clockTimer: Timer?
    private var reconnectWork: DispatchWorkItem?
    private var active = false
    private let reconnectDelay: TimeInterval = 5

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        active = true
        errorText = nil
        startClock()
        Task { await loadHistoryAndConnect() }
    }

    func stop() {
        active = false
        reconnectWork?.cancel()
        reconnectWork = nil
        OpenLogsSSEClient.shared.stop(notify: false)
        connection = .disconnected
        stopClock()
    }

    func clearLogs() {
        entries = []
        errorText = nil
    }

    func reconnectNow() {
        reconnectWork?.cancel()
        reconnectWork = nil
        Task { await connectStream() }
    }

    func reloadHistory() {
        Task { await loadHistoryAndConnect() }
    }

    private func loadHistoryAndConnect() async {
        isLoadingHistory = true
        errorText = nil
        defer { isLoadingHistory = false }

        do {
            let lines = try await service.fetchHistory(lines: 300)
            var built: [OpenLogEntry] = []
            built.reserveCapacity(lines.count)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let id = nextId
                nextId += 1
                built.append(OpenLogEntry.make(id: id, raw: trimmed))
            }
            if built.count > Self.maxLines {
                built = Array(built.suffix(Self.maxLines))
            }
            entries = built
            if built.isEmpty && errorText == nil {
                // 接口成功但无行：常见于远程部署 logs/application.log 路径为空
                errorText = "暂无历史日志。若为远程服务器，请确认服务端工作目录下存在 logs/application.log。"
            }
            if autoScroll { scrollToken += 1 }
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        guard active else { return }
        await connectStream()
    }

    private func connectStream() async {
        guard active else { return }
        reconnectWork?.cancel()
        reconnectWork = nil
        connection = .connecting

        let req: URLRequest
        do {
            req = try service.streamRequest()
        } catch {
            connection = .disconnected
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            scheduleReconnect()
            return
        }

        OpenLogsSSEClient.shared.start(
            request: req,
            onOpen: {
                DispatchQueue.main.async {
                    self.connection = .connected
                    self.errorText = nil
                }
            },
            onLine: { line in
                DispatchQueue.main.async {
                    self.appendLine(line)
                }
            },
            onClose: { error in
                DispatchQueue.main.async {
                    self.handleStreamClose(error)
                }
            }
        )
    }

    private func handleStreamClose(_ error: Error?) {
        guard active else {
            connection = .disconnected
            return
        }
        connection = .disconnected
        if let error = error {
            let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
            if !(error is CancellationError) {
                errorText = msg
            }
        }
        scheduleReconnect()
    }

    private func appendLine(_ raw: String) {
        guard active else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = nextId
        nextId += 1
        entries.append(OpenLogEntry.make(id: id, raw: trimmed))
        if entries.count > Self.maxLines {
            entries.removeFirst(entries.count - Self.maxLines)
        }
        if autoScroll {
            scrollToken += 1
        }
    }

    private func scheduleReconnect() {
        guard active else { return }
        reconnectWork?.cancel()
        let work = DispatchWorkItem {
            Task {
                await self.connectStream()
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    }

    private func startClock() {
        stopClock()
        tickClock()
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                self.tickClock()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        clockTimer = t
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func tickClock() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        clockText = f.string(from: Date())
    }
}
