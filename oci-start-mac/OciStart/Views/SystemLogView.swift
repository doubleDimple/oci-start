import SwiftUI
import Combine

/// SSE log viewer (Web: /system/logs or /system/openLogs)
final class LogStreamModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var connected = false
    @Published var autoScroll = true
    @Published var statusText = "未连接"

    private var task: URLSessionDataTask?
    private var session: URLSession?
    private let maxLines = 2000
    private var buffer = Data()

    func start(baseURL: String, isBootLog: Bool) {
        stop()
        guard var comps = URLComponents(string: "\(baseURL)/system/streamLogs") else { return }
        comps.queryItems = [URLQueryItem(name: "isBootLog", value: isBootLog ? "true" : "false")]
        guard let url = comps.url else { return }

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        let sess = URLSession(configuration: config, delegate: StreamDelegate(owner: self), delegateQueue: nil)
        session = sess
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        statusText = "连接中…"
        let t = sess.dataTask(with: req)
        task = t
        t.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        connected = false
        statusText = "已断开"
    }

    func clear() {
        DispatchQueue.main.async { self.lines = [] }
    }

    fileprivate func appendChunk(_ data: Data) {
        buffer.append(data)
        // parse by lines
        while let range = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                handleSSELine(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func handleSSELine(_ line: String) {
        if line.isEmpty { return }
        var text = line
        if text.hasPrefix("data:") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if text.isEmpty || text == ":" { return }
        DispatchQueue.main.async {
            self.connected = true
            self.statusText = "已连接"
            self.lines.append(text)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
        }
    }

    fileprivate func markConnected() {
        DispatchQueue.main.async {
            self.connected = true
            self.statusText = "已连接"
        }
    }

    fileprivate func markFailed(_ msg: String) {
        DispatchQueue.main.async {
            self.connected = false
            self.statusText = msg
        }
    }

    private final class StreamDelegate: NSObject, URLSessionDataDelegate {
        weak var owner: LogStreamModel?
        init(owner: LogStreamModel) { self.owner = owner }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                owner?.markConnected()
                completionHandler(.allow)
            } else {
                owner?.markFailed("连接失败")
                completionHandler(.cancel)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner?.appendChunk(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                owner?.markFailed(error.localizedDescription)
            } else {
                owner?.markFailed("流结束")
            }
        }
    }
}

struct SystemLogView: View {
    let isBootLog: Bool
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = LogStreamModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(model.connected ? AppTheme.success : AppTheme.muted(scheme))
                    .frame(width: 8, height: 8)
                Text(model.statusText)
                    .font(.caption)
                    .foregroundColor(AppTheme.muted(scheme))
                Spacer()
                Toggle("自动滚动", isOn: $model.autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.surface(scheme))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.text(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(12)
                }
                .background(AppTheme.pageBg(scheme))
                .onChange(of: model.lines.count) { count in
                    if model.autoScroll, count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle(isBootLog ? "开机日志" : "系统日志")
        .toolbar {
            ToolbarItem {
                Button(action: { model.clear() }) {
                    Label("清空", systemImage: "trash")
                }
            }
            ToolbarItem {
                Button(action: {
                    model.start(baseURL: appState.serverURL, isBootLog: isBootLog)
                }) {
                    Label("重连", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            model.start(baseURL: appState.serverURL, isBootLog: isBootLog)
        }
        .onDisappear {
            model.stop()
        }
    }
}
