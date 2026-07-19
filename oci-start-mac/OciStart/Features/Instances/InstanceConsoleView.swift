import SwiftUI
import AppKit
import WebKit

// MARK: - ViewModel

@MainActor
final class InstanceConsoleViewModel: ObservableObject {
    let item: InstanceItem
    private let session: AppSession
    private let ws = NativeWSClient()
    private var heartbeatTimer: Timer?
    /// 合并高频 SSH 日志，避免主线程被 @Published 刷爆导致按钮假死
    private var pendingLogLines: [String] = []
    private var logFlushScheduled = false

    @Published var statusText = "未连接"
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var logLines: [String] = []
    @Published var connectionCommand = ""
    @Published var websockifyPort: Int?
    /// RFB WebSocket URL，供 noVNC 画布加载
    @Published var vncWsURL: String?
    @Published var errorText: String?
    @Published var canvasStatus: String = ""
    /// websockify 缺失/启动失败时展示一键安装
    @Published var needsWebsockifyInstall = false
    @Published var isInstallingWebsockify = false

    init(item: InstanceItem, session: AppSession = .shared) {
        self.item = item
        self.session = session
        wireWS()
    }

    private func wireWS() {
        ws.onState = { [weak self] state in
            guard let self = self else { return }
            // NativeWSClient 已 hop 到主线程；直接更新，避免 Task 并发捕获编译问题
            switch state {
            case .connecting:
                self.isConnecting = true
                self.statusText = "WebSocket 连接中…"
            case .closed(let reason):
                self.stopHeartbeat()
                if self.isConnected || self.isConnecting {
                    self.isConnected = false
                    self.isConnecting = false
                    self.statusText = reason.map { "已断开：\($0)" } ?? "已断开"
                    self.vncWsURL = nil
                    self.websockifyPort = nil
                }
            default:
                break
            }
        }
        ws.onText = { [weak self] text in
            self?.handleWSMessage(text)
        }
    }

    func connect() {
        guard !item.id.isEmpty else {
            errorText = "实例 ID 无效"
            return
        }
        let tenantId = item.tenantIdStr.isEmpty ? "\(item.tenantId)" : item.tenantIdStr
        guard !tenantId.isEmpty, tenantId != "0" else {
            errorText = "缺少租户 ID"
            return
        }
        errorText = nil
        canvasStatus = ""
        isConnecting = true
        statusText = "正在创建控制台连接…"
        appendLog("▶ 创建 VNC 控制台连接…")

        do {
            let url = try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/console")
            ws.connect(url: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                self.ws.sendJSON([
                    "type": "create_connection",
                    "data": [
                        "instanceId": self.item.id,
                        "tenantId": tenantId,
                        "displayName": self.item.publicIps.isEmpty ? self.item.displayName : self.item.publicIps,
                        "connectionType": "vnc"
                    ]
                ])
                self.startHeartbeat()
            }
        } catch {
            isConnecting = false
            errorText = error.localizedDescription
            statusText = "连接失败"
        }
    }

    func disconnect() {
        stopHeartbeat()
        if isConnected || isConnecting {
            ws.sendJSON(["type": "disconnect"])
        }
        ws.disconnect(reason: nil)
        isConnected = false
        isConnecting = false
        statusText = "已断开"
        vncWsURL = nil
        websockifyPort = nil
        canvasStatus = ""
        appendLog("■ 已断开控制台")
    }

    func reboot() {
        guard AppAlert.confirm(title: "重新引导", message: "将对 \(item.displayName) 执行重引导（heavy restart）？") else { return }
        Task {
            do {
                let client = APIClient.shared
                let url = try client.makeURL(session.serverURL, path: "/oci/console/heavyNewRestart")
                let raw = try await client.postJSON(url, body: [
                    "instanceId": item.instanceId.isEmpty ? item.id : item.instanceId,
                    "tenantId": item.tenantIdStr.isEmpty ? "\(item.tenantId)" : item.tenantIdStr
                ])
                let r = InstanceJSON.successMessage(raw, fallback: "重引导请求已发送")
                if r.ok {
                    ToastCenter.shared.success(r.message)
                    appendLog("✅ \(r.message)")
                } else {
                    ToastCenter.shared.error(r.message)
                }
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func copyCommand() {
        let c = connectionCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else {
            ToastCenter.shared.error("暂无连接命令")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c, forType: .string)
        ToastCenter.shared.success("连接命令已复制")
    }

    /// 一键安装 websockify（oci-start-mac 本机优先用 Process 安装；连远程后端时走服务端 API）
    func installWebsockify() {
        guard !isInstallingWebsockify else { return }
        isInstallingWebsockify = true
        errorText = nil
        let local = AppSession.isLocalServerURL(session.serverURL)
        appendLog(local
            ? "▶ 正在本机安装 websockify（Mac 本地 pip/brew，约 1–2 分钟）…"
            : "▶ 正在通过服务端安装 websockify…")
        Task {
            let result: (ok: Bool, message: String, log: String, binary: String)
            if local {
                result = await Self.installWebsockifyOnMac()
            } else {
                result = await installWebsockifyViaBackend()
            }
            for line in result.log.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(line)
                if !s.isEmpty { appendLog("   \(s)") }
            }
            if result.ok {
                needsWebsockifyInstall = false
                let msg = result.message.isEmpty ? "websockify 安装成功" : result.message
                ToastCenter.shared.success(msg)
                appendLog("✅ \(msg)" + (result.binary.isEmpty ? "" : " (\(result.binary))"))
                appendLog("   请重新「创建 VNC 连接」以加载画面")
                if isConnected || isConnecting {
                    disconnect()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    connect()
                }
            } else {
                needsWebsockifyInstall = true
                let err = result.message.isEmpty ? "websockify 安装失败" : result.message
                errorText = err
                ToastCenter.shared.error(err)
                appendLog("❌ \(err)")
            }
            isInstallingWebsockify = false
        }
    }

    private func installWebsockifyViaBackend() async -> (ok: Bool, message: String, log: String, binary: String) {
        do {
            let client = APIClient.shared
            let url = try client.makeURL(session.serverURL, path: "/oci/console/websockify/install")
            let raw = try await client.postJSON(url, body: [:], longTimeout: true)
            let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
            let ok = (obj["success"] as? Bool) == true || (obj["installed"] as? Bool) == true
            return (
                ok,
                InstanceJSON.string(obj["message"]),
                InstanceJSON.string(obj["log"]),
                InstanceJSON.string(obj["binary"])
            )
        } catch {
            return (false, error.localizedDescription, "", "")
        }
    }

    /// Mac 本机安装：用登录 shell 的 PATH，避免 App 沙盒/精简 PATH 找不到 pip
    private nonisolated static func installWebsockifyOnMac() async -> (ok: Bool, message: String, log: String, binary: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // 已装则直接成功
                if let bin = Self.resolveWebsockifyOnMac() {
                    cont.resume(returning: (true, "websockify 已安装", "", bin))
                    return
                }

                let scripts: [(label: String, cmd: String)] = [
                    ("python3 -m pip install --user websockify",
                     "python3 -m pip install --user websockify"),
                    ("pip3 install --user websockify",
                     "pip3 install --user websockify"),
                    ("brew install websockify",
                     "command -v brew >/dev/null 2>&1 && brew install websockify")
                ]
                var logBuf = ""
                for item in scripts {
                    logBuf += "▶ \(item.label)\n"
                    let (code, out) = Self.runMacShell(item.cmd, timeoutSec: 180)
                    if !out.isEmpty {
                        logBuf += out
                        if !out.hasSuffix("\n") { logBuf += "\n" }
                    }
                    logBuf += "  exit=\(code)\n"
                    if let bin = Self.resolveWebsockifyOnMac() {
                        cont.resume(returning: (true, "websockify 安装成功", Self.trimInstallLog(logBuf), bin))
                        return
                    }
                }
                cont.resume(returning: (
                    false,
                    "本机安装失败。请确认已装 Python3/pip，或终端执行: pip3 install --user websockify",
                    Self.trimInstallLog(logBuf),
                    ""
                ))
            }
        }
    }

    private nonisolated static func resolveWebsockifyOnMac() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "websockify",
            "/opt/homebrew/bin/websockify",
            "/usr/local/bin/websockify",
            "\(home)/.local/bin/websockify"
        ]
        for c in candidates {
            if c.hasPrefix("/") {
                if FileManager.default.isExecutableFile(atPath: c) { return c }
            } else {
                let (code, out) = runMacShell("command -v \(c)", timeoutSec: 5)
                let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if code == 0, !path.isEmpty { return path }
            }
        }
        // python -m
        let (c3, _) = runMacShell("python3 -c 'import websockify'", timeoutSec: 8)
        if c3 == 0 { return "python3 -m websockify" }
        // 扫描 ~/Library/Python/*/bin/websockify
        let pyRoot = (home as NSString).appendingPathComponent("Library/Python")
        if let vers = try? FileManager.default.contentsOfDirectory(atPath: pyRoot) {
            for v in vers {
                let p = (pyRoot as NSString).appendingPathComponent("\(v)/bin/websockify")
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// 使用 zsh 登录 shell，继承用户终端 PATH（Homebrew / pyenv 等）
    private nonisolated static func runMacShell(_ command: String, timeoutSec: Int) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", command]
        var env = ProcessInfo.processInfo.environment
        let pathExtra = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        if let path = env["PATH"], !path.isEmpty {
            env["PATH"] = "\(pathExtra):\(path)"
        } else {
            env["PATH"] = "\(pathExtra):/usr/bin:/bin"
        }
        env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return (-1, error.localizedDescription)
        }

        let group = DispatchGroup()
        group.enter()
        var timedOut = false
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        let wait = group.wait(timeout: .now() + .seconds(timeoutSec))
        if wait == .timedOut {
            timedOut = true
            proc.terminate()
            // 再给一点时间收尸
            _ = group.wait(timeout: .now() + 2)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var out = String(data: data, encoding: .utf8) ?? ""
        if timedOut {
            out += "\n(超时 \(timeoutSec)s，已终止)\n"
            return (-1, out)
        }
        return (proc.terminationStatus, out)
    }

    private nonisolated static func trimInstallLog(_ s: String) -> String {
        if s.count <= 3500 { return s }
        return String(s.suffix(3500))
    }

    private func handleWSMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            appendLog(text)
            return
        }
        let type = InstanceJSON.string(obj["type"])
        switch type {
        case "heartbeat":
            ws.sendJSON(["type": "heartbeat_response", "timestamp": Int(Date().timeIntervalSince1970 * 1000)])
        case "heartbeat_response", "pong":
            break
        case "error":
            let msg = InstanceJSON.string(obj["message"])
            errorText = msg.isEmpty ? "控制台错误" : msg
            isConnecting = false
            isConnected = false
            statusText = "错误"
            appendLog("❌ \(errorText ?? "")")
            stopHeartbeat()
        case "vnc_ready":
            isConnecting = false
            isConnected = true
            let cmd = InstanceJSON.string(obj["command"])
            if !cmd.isEmpty { connectionCommand = cmd }

            // websockify 端口优先；不要用后端的本地 VNC port(5900) 冒充
            var port = parsePort(obj["websockifyPort"])
            if port == nil {
                // 仅当 websockifyPort 缺失时，尝试高端口的 port 字段
                if let p = parsePort(obj["port"]), p > 1024, p != 5900 { port = p }
            }
            websockifyPort = port

            let serverVncUrl = InstanceJSON.string(obj["vncUrl"])
            let serverMsg = InstanceJSON.string(obj["message"])
            let resolvedPort = port

            // 无 websockify 端口时不要假装画面可用
            if (port == nil || port == 0)
                && (serverVncUrl.isEmpty || serverVncUrl.hasPrefix("vnc://")) {
                statusText = "websockify 未就绪"
                canvasStatus = "websockify 启动失败"
                needsWebsockifyInstall = true
                appendLog("⚠️ 控制通道已建立，但 websockify 未启动，无法加载画面")
                if !serverMsg.isEmpty { appendLog("   \(serverMsg)") }
                appendLog("   oci-start-mac 本机未找到 websockify，可点「一键安装 websockify」")
                appendLog("   或终端手动: pip3 install --user websockify")
                errorText = "websockify 启动失败：请在 Mac 本机安装 websockify"
                return
            }

            needsWebsockifyInstall = false

            // 立刻更新文案，避免仍显示「点击创建连接」
            statusText = "即将连接画面…"
            canvasStatus = "websockify 已就绪"
            appendLog("✅ VNC 就绪 · websockify \(port.map(String.init) ?? "?")")
            if !serverVncUrl.isEmpty {
                appendLog("   服务端 vncUrl: \(serverVncUrl)")
            }

            // 对齐 Web：稍等 websockify 完全监听后再连 RFB；用 Task 保证 MainActor 不丢调用
            let portCap = resolvedPort
            let urlCap = serverVncUrl
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let self = self, self.isConnected else { return }
                self.applyVncURL(port: portCap, serverVncUrl: urlCap)
            }
        case "output":
            let line = InstanceJSON.string(obj["data"])
            if !line.isEmpty {
                appendLog(line)
                let lower = line.lowercased()
                if lower.contains("websockify 启动失败")
                    || lower.contains("未找到 websockify")
                    || lower.contains("请在服务端安装 websockify") {
                    needsWebsockifyInstall = true
                }
            }
        default:
            if type.isEmpty {
                appendLog(text)
            } else if let msg = obj["message"] as? String {
                appendLog(msg)
            } else if let dataStr = obj["data"] as? String {
                appendLog(dataStr)
            }
        }
    }

    private func parsePort(_ any: Any?) -> Int? {
        guard let any = any else { return nil }
        if let n = any as? Int, n > 0 { return n }
        if let n = any as? Int64, n > 0 { return Int(n) }
        if let n = any as? NSNumber {
            let v = n.intValue
            return v > 0 ? v : nil
        }
        if let s = any as? String, let v = Int(s), v > 0 { return v }
        return nil
    }

    /// 与 Web `connectToVncWebSocket` 一致的 URL 规则
    private func applyVncURL(port: Int?, serverVncUrl: String) {
        var base = session.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        let isHTTPS = base.lowercased().hasPrefix("https")

        // 1) 服务端下发的完整 ws/wss URL（含公网 IP + websockify 端口）
        //    HTTP 客户端直接用；HTTPS 必须走反代路径，避免混合内容
        if !isHTTPS, serverVncUrl.hasPrefix("ws://") || serverVncUrl.hasPrefix("wss://") {
            let url = serverVncUrl.hasSuffix("/") ? serverVncUrl : serverVncUrl + "/"
            vncWsURL = url
            statusText = "正在连接画面…"
            appendLog("🔗 VNC WS (server): \(url)")
            return
        }

        if isHTTPS {
            // 反代路径：wss://host/websockify/{port}（对齐 console_terminal.ftl）
            guard let port = port, port > 0 else {
                appendLog("❌ HTTPS 模式需要 websockifyPort，并配置 Nginx /websockify/")
                canvasStatus = "缺少 websockify 端口"
                statusText = "无法连接画面"
                return
            }
            guard let u = URL(string: base), let host = u.host else {
                appendLog("❌ 无法解析服务器地址")
                statusText = "无法连接画面"
                return
            }
            let hostPart: String
            if let p = u.port {
                hostPart = "\(host):\(p)"
            } else {
                hostPart = host
            }
            let wsUrl = "wss://\(hostPart)/websockify/\(port)"
            vncWsURL = wsUrl
            statusText = "正在连接画面…"
            appendLog("🔗 VNC WS: \(wsUrl)")
            return
        }

        // 2) HTTP：优先用服务端公网 IP 拼端口；否则用 session host
        if let port = port, port > 0 {
            // 从 server vncUrl 提取 host（更准，避免 127.0.0.1 打到本机）
            if let fromServer = hostFromWSURL(serverVncUrl) {
                let wsUrl = "ws://\(fromServer):\(port)/"
                vncWsURL = wsUrl
                statusText = "正在连接画面…"
                appendLog("🔗 VNC WS: \(wsUrl)")
                return
            }
            let host: String
            if let u = URL(string: base), let h = u.host {
                host = h
            } else {
                host = base
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                    .split(separator: "/").first.map(String.init) ?? base
            }
            let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
            // 本机嵌入后端时 session host 可能是 127.0.0.1，websockify 在远端——必须用公网 IP
            if hostOnly == "127.0.0.1" || hostOnly == "localhost" {
                appendLog("⚠️ 服务端地址是本机，但 websockify 在远端；请使用服务端下发的 vncUrl")
                if serverVncUrl.hasPrefix("ws") {
                    vncWsURL = serverVncUrl.hasSuffix("/") ? serverVncUrl : serverVncUrl + "/"
                    statusText = "正在连接画面…"
                    appendLog("🔗 VNC WS (server fallback): \(vncWsURL ?? serverVncUrl)")
                    return
                }
            }
            let wsUrl = "ws://\(hostOnly):\(port)/"
            vncWsURL = wsUrl
            statusText = "正在连接画面…"
            appendLog("🔗 VNC WS: \(wsUrl)")
            appendLog("   若画面连不上：请放行服务端防火墙该端口，或改用 HTTPS + /websockify/ 反代")
            return
        }

        if !serverVncUrl.isEmpty, serverVncUrl.hasPrefix("ws") {
            vncWsURL = serverVncUrl.hasSuffix("/") ? serverVncUrl : serverVncUrl + "/"
            statusText = "正在连接画面…"
            appendLog("🔗 VNC WS (server): \(vncWsURL ?? serverVncUrl)")
            return
        }

        appendLog("❌ 无法构造 VNC WebSocket 地址（websockify 未返回端口）")
        canvasStatus = "无法构造 VNC 地址"
        statusText = "无法连接画面"
    }

    private func hostFromWSURL(_ s: String) -> String? {
        guard let u = URL(string: s), let h = u.host, !h.isEmpty else { return nil }
        return h
    }

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.ws.sendJSON(["type": "ping", "timestamp": Int(Date().timeIntervalSince1970 * 1000)])
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func appendLog(_ s: String) {
        let line = s.trimmingCharacters(in: CharacterSet.newlines)
        guard !line.isEmpty else { return }
        pendingLogLines.append(line)
        scheduleLogFlush()
    }

    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            self.logFlushScheduled = false
            guard !self.pendingLogLines.isEmpty else { return }
            var next = self.logLines
            next.append(contentsOf: self.pendingLogLines)
            self.pendingLogLines.removeAll(keepingCapacity: true)
            if next.count > 400 {
                next.removeFirst(next.count - 400)
            }
            self.logLines = next
        }
    }

    func onCanvasMessage(_ msg: String) {
        canvasStatus = msg
        appendLog("🖥 \(msg)")
        if msg.contains("已连接") {
            statusText = "画面已连接"
        } else if msg.contains("断开") || msg.contains("失败") {
            statusText = msg
        }
    }

    func teardown() {
        pendingLogLines.removeAll()
        logFlushScheduled = false
        disconnect()
    }
}

// MARK: - noVNC inline HTML（仅协议画布，非整页 FTL）

enum InstanceNoVNCHTML {
    static func page(wsURL: String) -> String {
        // 使用 IIFE + dynamic import，兼容 WKWebView；参数对齐 Web RFB 配置
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <style>
          html,body{margin:0;height:100%;background:#000;color:#c9d1d9;font-family:-apple-system,sans-serif;overflow:hidden}
          #screen{position:absolute;inset:0;background:#000}
          #status{position:absolute;left:12px;bottom:10px;font-size:12px;opacity:.85;z-index:2;
            background:rgba(0,0,0,.55);padding:4px 8px;border-radius:6px;pointer-events:none}
        </style>
        </head>
        <body>
          <div id="screen"></div>
          <div id="status">正在加载 noVNC…</div>
          <script type="module">
            const wsUrl = \(jsonString(wsURL));
            const el = document.getElementById('screen');
            const st = document.getElementById('status');
            function post(msg) {
              try { window.webkit.messageHandlers.vnc.postMessage(String(msg)); } catch (e) {}
              st.textContent = msg;
            }
            try {
              const mod = await import('https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/lib/rfb.js');
              const RFB = mod.default;
              post('正在连接 VNC…');
              const rfb = new RFB(el, wsUrl, {
                shared: true,
                wsProtocols: ['binary']
              });
              rfb.scaleViewport = true;
              rfb.resizeSession = false;
              rfb.qualityLevel = 9;
              rfb.compressionLevel = 0;
              rfb.addEventListener('connect', () => post('VNC 画面已连接'));
              rfb.addEventListener('disconnect', (e) => {
                post(e.detail && e.detail.clean ? 'VNC 已断开' : 'VNC 异常断开');
              });
              rfb.addEventListener('securityfailure', (e) => {
                post('VNC 安全校验失败: ' + (e.detail && e.detail.status || ''));
              });
              rfb.addEventListener('credentialsrequired', () => {
                post('需要 VNC 密码');
                const p = prompt('VNC 密码');
                if (p != null) rfb.sendCredentials({ password: p });
              });
              window.__rfb = rfb;
            } catch (e) {
              post('noVNC 加载失败: ' + e);
            }
          </script>
        </body></html>
        """
    }

    private static func jsonString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: [])
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }
}

// MARK: - VNC canvas

struct NoVNCCanvas: NSViewRepresentable {
    let wsURL: String?
    var onMessage: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        conf.userContentController.add(context.coordinator, name: "vnc")
        // 允许内联媒体 / 模块脚本
        if #available(macOS 11.0, *) {
            conf.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let wv = WKWebView(frame: .zero, configuration: conf)
        wv.setValue(true, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        let key = wsURL ?? ""
        guard key != context.coordinator.lastKey else { return }
        context.coordinator.lastKey = key
        if let ws = wsURL, !ws.isEmpty {
            let html = InstanceNoVNCHTML.page(wsURL: ws)
            // baseURL 使用 CDN 域，便于 ES module 解析相对资源
            nsView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/"))
        } else {
            nsView.loadHTMLString(
                """
                <html><body style="margin:0;background:#0d1117;color:#8b949e;font:13px -apple-system,sans-serif;
                display:flex;align-items:center;justify-content:center;height:100%">
                等待 VNC 就绪…</body></html>
                """,
                baseURL: nil
            )
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "vnc")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastKey: String = ""
        var onMessage: ((String) -> Void)?
        weak var webView: WKWebView?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let text = "\(message.body)"
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(text)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?("页面加载失败: \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?("页面错误: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Full page view

struct InstanceConsoleView: View {
    let item: InstanceItem
    var onBack: (() -> Void)?
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: InstanceConsoleViewModel

    init(item: InstanceItem, onBack: (() -> Void)? = nil) {
        self.item = item
        self.onBack = onBack
        _model = StateObject(wrappedValue: InstanceConsoleViewModel(item: item))
    }

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(2)
            toolbar
                .zIndex(2)
            HStack(spacing: 0) {
                ZStack {
                    Color.black
                    // 仅在有 VNC URL 时挂 WKWebView，避免空白 WebView 抢焦点/挡事件
                    if model.vncWsURL != nil {
                        NoVNCCanvas(wsURL: model.vncWsURL) { msg in
                            model.onCanvasMessage(msg)
                        }
                    }
                    if model.vncWsURL == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "tv")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(Color.white.opacity(0.35))
                            Text(canvasPlaceholderText)
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.55))
                            if model.needsWebsockifyInstall {
                                Text("Mac 本机未安装 websockify，画面无法显示")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "f85149").opacity(0.9))
                                AppButton(
                                    title: model.isInstallingWebsockify ? "正在安装…" : "一键安装 websockify",
                                    systemImage: "arrow.down.circle",
                                    kind: .primary,
                                    isLoading: model.isInstallingWebsockify
                                ) {
                                    model.installWebsockify()
                                }
                                .disabled(model.isInstallingWebsockify)
                            } else if model.isConnected || model.isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                    .padding(.top, 4)
                            }
                        }
                        // 安装按钮需要可点；其余占位文案不挡事件
                        .allowsHitTesting(model.needsWebsockifyInstall)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                logPanel
                    .frame(width: 300)
            }
            .zIndex(0)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(AppTheme.pageBg(dark))
        .onAppear {
            // 进页即清所有窗内菜单浮层，防止残留 catcher/panel 挡死整窗
            FloatingMenuDismiss.all()
        }
        .onDisappear { model.teardown() }
    }

    private var canvasPlaceholderText: String {
        if model.vncWsURL != nil { return "" }
        if model.isConnecting { return "正在建立控制通道…" }
        if model.isConnected {
            if model.statusText.contains("即将") || model.statusText.contains("就绪") {
                return "即将连接画面…"
            }
            return model.statusText.isEmpty ? "正在准备画面…" : model.statusText
        }
        return "点击「创建 VNC 连接」开始"
    }

    private var header: some View {
        HStack(spacing: 10) {
            if onBack != nil {
                AppButton(title: "返回", systemImage: "chevron.left", kind: .secondary) {
                    model.teardown()
                    onBack?()
                }
            }
            Image(systemName: "tv")
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text("控制台 — \(item.displayName.isEmpty ? "实例" : item.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                Text(model.statusText)
                    .font(.system(size: 11))
                    .foregroundColor(
                        model.statusText.contains("已连接")
                            ? Color(hex: "3fb950")
                            : AppTheme.sidebarText(dark)
                    )
            }
            Spacer()
            if !model.canvasStatus.isEmpty {
                StatusBadge(
                    text: model.canvasStatus,
                    tone: model.canvasStatus.contains("已连接") ? .success
                        : (model.canvasStatus.contains("失败") || model.canvasStatus.contains("断开") ? .danger : .info)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.sidebarBg(dark))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.55)),
            alignment: .bottom
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("公网 IP：\(item.publicIps.isEmpty ? "—" : item.publicIps)")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            if let port = model.websockifyPort {
                Text("websockify：\(port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            Spacer()
            if model.needsWebsockifyInstall || model.isInstallingWebsockify {
                AppButton(
                    title: model.isInstallingWebsockify ? "安装中…" : "安装 websockify",
                    systemImage: "arrow.down.circle",
                    kind: .secondary,
                    isLoading: model.isInstallingWebsockify
                ) {
                    model.installWebsockify()
                }
                .disabled(model.isInstallingWebsockify)
            }
            if !model.connectionCommand.isEmpty {
                AppButton(title: "复制命令", systemImage: "doc.on.doc", kind: .secondary) {
                    model.copyCommand()
                }
            }
            AppButton(title: "重引导", systemImage: "arrow.clockwise", kind: .secondary) {
                model.reboot()
            }
            if model.isConnected || model.isConnecting {
                AppButton(title: "断开", kind: .danger) { model.disconnect() }
            } else {
                AppButton(
                    title: "创建 VNC 连接",
                    systemImage: "plus",
                    kind: .primary,
                    isLoading: model.isConnecting
                ) { model.connect() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.sidebarBg(dark).opacity(0.65))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("连接日志")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.sidebarText(dark))
                .padding(10)
            Divider().opacity(0.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let err = model.errorText, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "f85149"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
        }
        .background(AppTheme.sidebarBg(dark))
        .overlay(
            Rectangle().frame(width: 1).foregroundColor(AppTheme.border(dark).opacity(0.55)),
            alignment: .leading
        )
    }
}
