import SwiftUI
import AppKit
import WebKit
import CoreFoundation

private func consoleText(_ chinese: String, _ english: String) -> String {
    (UserDefaults.standard.string(forKey: "appLocale") ?? "zh_CN").hasPrefix("en") ? english : chinese
}

enum ConsoleModal: Equatable { case create, credentials, text, restart }
enum ConsolePhase: Equatable {
    case idle, preparing, connecting, credentials, connected, manual, closed, error
    var title: String {
        switch self {
        case .idle: return consoleText("未连接", "Idle")
        case .preparing: return consoleText("准备控制台", "Preparing console")
        case .connecting: return consoleText("连接画面", "Connecting display")
        case .credentials: return consoleText("等待认证", "Authentication required")
        case .connected: return consoleText("已连接", "Connected")
        case .manual: return consoleText("需手动连接", "Manual connection")
        case .closed: return consoleText("已断开", "Disconnected")
        case .error: return consoleText("连接失败", "Connection failed")
        }
    }
}
enum ConsoleTextOutcome: Equatable { case idle, sent, interrupted }
enum ConsoleRestartOutcome: Equatable { case idle, sending, accepted, uncertain, failed }

@MainActor
final class InstanceConsoleViewModel: ObservableObject {
    let item: InstanceItem
    let canvas = ConsoleCanvasBridge()
    private let session: AppSession
    private let ws = NativeWSClient()
    private var active = false
    private var epoch = UUID().uuidString
    private var metadataVersion = 0
    private var prepareID: String?
    private var textID: String?
    private var deadline: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var heartbeatTicks = 0
    private var idleTimer: Timer?
    private var activityMonitor: Any?
    private var lastActivity: Date?
    private var pendingLog = ""
    private var logFlush: DispatchWorkItem?

    @Published private(set) var phase: ConsolePhase = .idle
    @Published private(set) var metadataLoading = false
    @Published private(set) var metadataError: String?
    @Published private(set) var preparingClient = false
    @Published private(set) var bridgeReady = false
    @Published private(set) var errorText: String?
    @Published private(set) var logText = ""
    @Published private(set) var outputTruncated = false
    @Published private(set) var connectionCommand = ""
    @Published private(set) var connectionID = ""
    @Published private(set) var desktopName = ""
    @Published private(set) var websockifyPort: Int?
    @Published private(set) var vncWsURL: String?
    @Published private(set) var modal: ConsoleModal?
    @Published var fitScreen = false
    @Published var viewOnly = false
    @Published var detailsOpen = false
    @Published var followOutput = true
    @Published private(set) var isFullscreen = false
    @Published private(set) var idleRemainingSeconds = 1800
    @Published private(set) var idleWarning = false
    @Published private(set) var credentialTypes: [String] = []
    @Published var credentialUsername = ""
    @Published var credentialPassword = ""
    @Published var credentialTarget = ""
    @Published var textDraft = ""
    @Published private(set) var textPending = false
    @Published private(set) var textOutcome: ConsoleTextOutcome = .idle
    @Published private(set) var textError: String?
    @Published private(set) var restartOutcome: ConsoleRestartOutcome = .idle
    @Published private(set) var restartError: String?
    @Published var restartReviewed = false
    @Published var needsWebsockifyInstall = false
    @Published var isInstallingWebsockify = false

    private struct Metadata {
        let localID: String
        let ociID: String
        let tenantID: String
        let name: String
        let ip: String
    }
    @Published private var context: Metadata?
    var isConnected: Bool { phase == .connected }
    var isConnecting: Bool { phase == .preparing || phase == .connecting || phase == .credentials }
    var hasSession: Bool { isConnecting || isConnected || phase == .manual }
    var isRebooting: Bool { restartOutcome == .sending }
    var busy: Bool { preparingClient || textPending || isRebooting || isInstallingWebsockify }
    var statusText: String { preparingClient ? consoleText("加载控制台引擎", "Loading console client") : phase.title }
    var instanceLabel: String { context.map { $0.name.isEmpty ? $0.ip : $0.name } ?? item.displayName }
    var instanceIP: String { context?.ip ?? item.publicIps }
    var canCreate: Bool { active && context != nil && bridgeReady && !metadataLoading && !busy && !isConnecting }
    var canRestart: Bool { active && isConnected && context != nil && !metadataLoading && !busy }
    var idleTime: String { String(format: "%d:%02d", idleRemainingSeconds / 60, idleRemainingSeconds % 60) }
    var canInput: Bool { isConnected && !viewOnly && !textPending && modal == nil }

    init(item: InstanceItem, session: AppSession = .shared) {
        self.item = item
        self.session = session
        canvas.onEvent = { [weak self] event in self?.handleCanvasEvent(event) }
        ws.onText = { [weak self] text in self?.handleWSMessage(text) }
        ws.onState = { [weak self] state in
            guard let self = self, self.active else { return }
            if case .closed(let reason) = state, self.hasSession {
                self.fail(reason ?? consoleText("控制通道已断开", "The control connection closed"))
            }
        }
    }

    func start() {
        guard !active else { return }
        active = true
        reloadMetadata()
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            Task { @MainActor in
                if event.window === self.canvas.webView?.window { self.touch() }
            }
            return event
        }
    }

    private func metadata() async throws -> Metadata {
        func positiveID(_ value: Any?) -> String? {
            guard let string = value as? String, let id = Int64(string), id > 0,
                  String(id) == string else { return nil }
            return string
        }
        guard positiveID(item.id) != nil else { throw APIError.invalidURL }
        let url = try APIClient.shared.makeURL(session.serverURL, path: "/oci/console/metadata/\(item.id)")
        let raw = try await APIClient.shared.getJSON(url)
        guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              root["success"] as? Bool == true, let data = root["data"] as? [String: Any],
              positiveID(data["instanceId"]) == item.id, let tenant = positiveID(data["tenantId"]),
              let oci = data["ociInstanceId"] as? String, oci.hasPrefix("ocid1.instance."),
              oci.count > "ocid1.instance.".count,
              oci.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let name = data["instanceName"] as? String, let ip = data["instanceIp"] as? String
        else { throw APIError.serverMessage(consoleText("实例上下文无法确认，请刷新重试。", "Instance context is unconfirmed. Reload to retry.")) }
        return Metadata(localID: item.id, ociID: oci, tenantID: tenant, name: name, ip: ip)
    }

    func reloadMetadata() {
        guard active, !metadataLoading, !hasSession, !busy else { return }
        metadataVersion += 1
        let version = metadataVersion
        metadataLoading = true
        metadataError = nil
        Task {
            do {
                let value = try await metadata()
                guard active, version == metadataVersion else { return }
                context = value
            } catch {
                guard active, version == metadataVersion else { return }
                context = nil
                metadataError = error.localizedDescription
            }
            if version == metadataVersion { metadataLoading = false }
        }
    }

    func requestCreate() {
        guard canCreate else { return }
        openModal(.create)
    }

    func createConnection() {
        guard canCreate, modal == .create else { return }
        preparingClient = true
        errorText = nil
        let token = UUID().uuidString
        prepareID = token
        // This command only imports noVNC; it never opens a socket or creates cloud resources.
        canvas.send(["kind": "prepare", "requestID": token]) { [weak self] accepted in
            guard let self = self, self.prepareID == token, !accepted else { return }
            self.prepareID = nil
            self.preparingClient = false
            self.errorText = consoleText("控制台引擎尚未就绪，请重试。", "The console client is not ready. Retry.")
        }
    }

    private func beginConnection() {
        guard active, preparingClient, let context = context else { return }
        preparingClient = false
        prepareID = nil
        release(.closed)
        epoch = UUID().uuidString
        phase = .preparing
        modal = nil
        viewOnly = false
        desktopName = ""
        connectionCommand = ""
        connectionID = ""
        logText = ""
        pendingLog = ""
        outputTruncated = false
        needsWebsockifyInstall = false
        errorText = nil
        do {
            ws.connect(url: try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/console"))
            ws.sendJSON(["type": "create_connection", "data": [
                "instanceId": context.localID, "tenantId": context.tenantID,
                "displayName": context.ip.isEmpty ? context.name : context.ip, "connectionType": "vnc"
            ]])
            setDeadline(seconds: 300, message: consoleText("控制台准备超时，请核对服务端状态。", "Console preparation timed out. Review the server state."))
            startHeartbeat()
        } catch { fail(error.localizedDescription) }
    }

    func disconnect() {
        guard !busy else { return }
        release(.closed)
    }

    private func release(_ next: ConsolePhase) {
        let previous = epoch
        epoch = UUID().uuidString
        deadline?.cancel()
        deadline = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        if hasSession { ws.sendJSON(["type": "disconnect"]) }
        phase = next
        ws.disconnect(reason: nil)
        canvas.send(["kind": "disconnect", "epoch": previous])
        if textPending { textOutcome = .interrupted }
        textPending = false
        textID = nil
        vncWsURL = nil
        websockifyPort = nil
        lastActivity = nil
        idleRemainingSeconds = 1800
        idleWarning = false
        if modal == .credentials { modal = nil }
        clearCredentials()
        flushLogs()
        // Keep this instance's command, connection ID and bounded logs until new creation or leaving.
    }

    private func fail(_ message: String) {
        release(.error)
        errorText = message
    }

    private func setDeadline(seconds: Double, message: String) {
        deadline?.cancel()
        let generation = epoch
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.epoch == generation, self.hasSession else { return }
            self.fail(message)
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func startHeartbeat() {
        heartbeatTicks = 0
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.heartbeatTick() }
        }
    }
    private func heartbeatTick() {
        guard active, hasSession else { return }
        heartbeatTicks += 1
        if heartbeatTicks % 3 == 0 { ws.sendJSON(["type": "heartbeat", "timestamp": Int(Date().timeIntervalSince1970 * 1000)]) }
        if phase != .preparing { ws.sendJSON(["type": "ping", "timestamp": Int(Date().timeIntervalSince1970 * 1000)]) }
    }

    func touch() {
        guard isConnected else { return }
        if let last = lastActivity, Date().timeIntervalSince(last) >= 1800 {
            fail(consoleText("闲置超过 30 分钟，连接已断开。", "The connection closed after 30 minutes of inactivity."))
            return
        }
        if let last = lastActivity, Date().timeIntervalSince(last) < 0.25 { return }
        lastActivity = Date()
        canvas.send(["kind": "touch", "epoch": epoch, "deadline": Date().addingTimeInterval(1800).timeIntervalSince1970 * 1000])
        idleRemainingSeconds = 1800
        idleWarning = false
    }

    func checkIdle() {
        guard active, isConnected, let last = lastActivity else { return }
        let remaining = max(0, Int(ceil(1800 - Date().timeIntervalSince(last))))
        idleRemainingSeconds = remaining
        idleWarning = remaining > 0 && remaining <= 60
        if remaining == 0 { fail(consoleText("闲置超过 30 分钟，连接已断开。", "The connection closed after 30 minutes of inactivity.")) }
    }

    private func handleWSMessage(_ text: String) {
        guard active, hasSession else { return }
        guard text.utf16.count <= 1024 * 1024, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            fail(consoleText("控制台消息无效。", "Invalid console message."))
            return
        }
        switch type {
        case "heartbeat": ws.sendJSON(["type": "heartbeat_response", "timestamp": Int(Date().timeIntervalSince1970 * 1000)])
        case "heartbeat_response", "pong": break
        case "output":
            guard let output = object["data"] as? String else { fail(consoleText("输出消息无效。", "Invalid output message.")); return }
            appendOutput(output)
        case "error":
            guard let message = object["message"] as? String else { fail(consoleText("控制台消息无效。", "Invalid console message.")); return }
            fail(String(message.prefix(1000)))
        case "vnc_ready":
            guard phase == .preparing, let id = object["connectionId"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let command = object["command"] as? String, parsePort(object["port"]) != nil else {
                fail(consoleText("控制台准备响应无效。", "Invalid console preparation response.")); return
            }
            connectionID = id
            connectionCommand = command
            if let message = object["message"] as? String, !message.isEmpty { appendLog(message) }
            if object["websockifyPort"] == nil || object["websockifyPort"] is NSNull {
                phase = .manual
                needsWebsockifyInstall = true
                detailsOpen = true
                setDeadline(seconds: 300, message: consoleText("手动连接等待超时。", "Manual connection preparation timed out."))
                return
            }
            guard let port = parsePort(object["websockifyPort"]), let url = vncURL(port: port) else {
                fail(consoleText("websockify 端口无效。", "Invalid websockify port.")); return
            }
            phase = .connecting
            websockifyPort = port
            vncWsURL = url
            let generation = epoch
            canvas.send(["kind": "connect", "epoch": generation, "url": url,
                         "scale": fitScreen, "viewOnly": viewOnly, "active": modal == nil]) { [weak self] accepted in
                guard let self = self, self.epoch == generation, self.phase == .connecting, !accepted else { return }
                self.fail(consoleText("无法启动 VNC 画面。", "Could not start the VNC display."))
            }
            setDeadline(seconds: 30, message: consoleText("VNC 画面连接超时。", "The VNC display connection timed out."))
        default: fail(consoleText("未知控制台消息。", "Unknown console message."))
        }
    }

    private func parsePort(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 1, number.doubleValue <= 65535 else { return nil }
        return number.intValue
    }

    private func vncURL(port: Int) -> String? {
        guard var parts = URLComponents(string: session.serverURL),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = scheme == "https" ? "wss" : "ws"
        parts.query = nil
        parts.fragment = nil
        if scheme == "https" { parts.path = "/websockify/\(port)" }
        else { parts.port = port; parts.path = "/" }
        return parts.url?.absoluteString
    }

    private func handleCanvasEvent(_ event: [String: Any]) {
        guard active, let kind = event["kind"] as? String else { return }
        if kind == "bridgeReady" { bridgeReady = true; syncFullscreen(); return }
        if kind == "bridgeError" {
            bridgeReady = false
            preparingClient = false
            prepareID = nil
            errorText = consoleText("控制台画布未能加载，请返回后重新进入。", "The console canvas could not load. Leave and reopen it.")
            if hasSession { fail(errorText ?? "") }
            return
        }
        if kind == "runtimeReady" || kind == "runtimeError" {
            guard let token = event["requestID"] as? String, token == prepareID, preparingClient else { return }
            if kind == "runtimeReady" { beginConnection() }
            else {
                prepareID = nil
                preparingClient = false
                errorText = consoleText("noVNC 引擎加载失败，请检查网络后重试；未创建云控制台。", "noVNC could not load. Check the network and retry; no cloud console was created.")
            }
            return
        }
        guard event["epoch"] as? String == epoch else { return }
        switch kind {
        case "connected":
            guard phase == .connecting || phase == .credentials, vncWsURL != nil else { return }
            phase = .connected
            deadline?.cancel()
            deadline = nil
            clearCredentials()
            if modal == .credentials { modal = nil }
            errorText = nil
            touch()
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in self.checkIdle() }
            }
            updatePresentation()
            focusCanvas()
        case "disconnected":
            if hasSession {
                let reason = event["reason"] as? String ?? ""
                fail(reason.isEmpty ? consoleText("VNC 画面已断开。", "The VNC display disconnected.") : String(reason.prefix(1000)))
            }
        case "credentials":
            guard phase == .connecting || phase == .credentials else { return }
            let requested = event["types"] as? [String] ?? []
            let types = requested.isEmpty ? ["password"] : requested
            guard types.allSatisfy({ ["password", "username", "target"].contains($0) }) else {
                fail(consoleText("不支持此 VNC 认证方式。", "This VNC authentication method is not supported.")); return
            }
            clearCredentials()
            credentialTypes = types
            phase = .credentials
            openModal(.credentials)
            setDeadline(seconds: 300, message: consoleText("VNC 认证等待超时。", "VNC authentication timed out."))
        case "securityFailure":
            let reason = event["reason"] as? String ?? ""
            fail(consoleText("VNC 安全校验失败。", "VNC security verification failed.") + String(reason.prefix(1000)))
        case "rendererError":
            fail(consoleText("VNC 画面初始化失败。", "The VNC display failed to initialize."))
        case "activity": touch()
        case "idleExpired": fail(consoleText("闲置超过 30 分钟，连接已断开。", "The connection closed after 30 minutes of inactivity."))
        case "desktopName": desktopName = String((event["name"] as? String ?? "").prefix(1000))
        case "textFinished":
            guard let token = event["requestID"] as? String, token == textID else { return }
            textPending = false
            textID = nil
            textOutcome = event["sent"] as? Bool == true && isConnected ? .sent : .interrupted
            touch()
        case "inputError":
            let message = consoleText("输入未能完整发送，可能已发送部分内容，请先核对远端。", "Input may have been partially sent. Check the remote screen before sending again.")
            textError = message
            if modal != .text { errorText = message }
        default: break
        }
    }

    func updatePresentation() {
        canvas.send(["kind": "presentation", "epoch": epoch, "scale": fitScreen,
                     "viewOnly": viewOnly, "active": modal == nil && !busy])
        touch()
    }
    private func openModal(_ value: ConsoleModal) {
        modal = value
        updatePresentation()
    }
    func closeModal() {
        guard !busy else { return }
        if modal == .credentials { release(.closed) }
        modal = nil
        clearCredentials()
        updatePresentation()
        focusCanvas()
    }
    func submitCredentials() {
        guard modal == .credentials, phase == .credentials else { return }
        var values: [String: String] = [:]
        if credentialTypes.contains("username") { values["username"] = credentialUsername }
        if credentialTypes.contains("password") { values["password"] = credentialPassword }
        if credentialTypes.contains("target") { values["target"] = credentialTarget }
        let generation = epoch
        canvas.send(["kind": "credentials", "epoch": generation, "values": values]) { [weak self] accepted in
            guard let self = self, self.epoch == generation, self.phase == .credentials else { return }
            if !accepted { self.fail(consoleText("VNC 认证提交失败。", "VNC authentication could not be submitted.")); return }
            self.modal = nil
            self.clearCredentials()
            self.phase = .connecting
            self.updatePresentation()
            self.setDeadline(seconds: 30, message: consoleText("VNC 画面连接超时。", "The VNC display connection timed out."))
        }
    }
    private func clearCredentials() {
        credentialUsername = ""
        credentialPassword = ""
        credentialTarget = ""
        credentialTypes = []
    }
    func sendCtrlAltDel() {
        guard canInput else { return }
        let generation = epoch
        canvas.send(["kind": "ctrlAltDel", "epoch": generation]) { [weak self] accepted in
            guard let self = self, self.epoch == generation, !accepted else { return }
            self.errorText = consoleText("按键发送结果无法确认，请核对远端。", "The key input is unconfirmed. Review the remote screen.")
        }
        touch()
        focusCanvas()
    }
    func openText() {
        guard isConnected, !viewOnly, !busy else { return }
        openModal(.text)
    }
    func sendText() {
        guard modal == .text, isConnected, !viewOnly, !textPending, textOutcome == .idle, !textDraft.isEmpty else { return }
        guard textDraft.utf16.count <= 65536 else {
            textError = consoleText("文本最多 65,536 个 UTF-16 单元。", "Text is limited to 65,536 UTF-16 units."); return
        }
        textError = nil
        let token = UUID().uuidString
        let generation = epoch
        textID = token
        textPending = true
        canvas.send(["kind": "text", "epoch": generation, "requestID": token, "text": textDraft]) { [weak self] accepted in
            guard let self = self, self.epoch == generation, self.textID == token, !accepted else { return }
            self.textPending = false
            self.textID = nil
            self.textOutcome = .interrupted
            self.textError = consoleText("文本无法发送，请核对内容与连接状态。", "Text could not be sent. Check its contents and the connection.")
        }
    }
    func cancelText() {
        guard textPending else { return }
        canvas.send(["kind": "cancelText", "epoch": epoch])
        textID = nil
        textPending = false
        textOutcome = .interrupted
    }
    func newText() {
        guard !textPending else { return }
        textDraft = ""
        textOutcome = .idle
        textError = nil
    }
    func pasteLocalText() {
        guard !textPending, textOutcome == .idle else { return }
        if let value = NSPasteboard.general.string(forType: .string) {
            guard value.utf16.count <= 65536 else { textError = consoleText("剪贴板文本太长。", "Clipboard text is too long."); return }
            textDraft = value
        }
    }

    func requestRestart() {
        guard canRestart else { return }
        openModal(.restart)
    }
    func reboot() {
        guard canRestart, modal == .restart, restartOutcome == .idle || restartOutcome == .failed,
              let context = context else { return }
        restartOutcome = .sending
        restartReviewed = false
        restartError = nil
        updatePresentation()
        Task {
            do {
                let client = APIClient.shared
                let url = try client.makeURL(session.serverURL, path: "/oci/console/heavyNewRestart")
                let raw = try await client.postJSON(url, body: ["instanceId": context.ociID, "tenantId": context.tenantID], longTimeout: true)
                let receipt = InstanceJSON.successMessage(raw)
                guard receipt.ok else { throw APIError.serverMessage(receipt.message) }
                restartOutcome = .accepted
            } catch {
                restartOutcome = .uncertain
                restartError = consoleText("重引导结果未知，请核对实例状态，勿重复提交。", "The restart result is unknown. Review the instance state before another submission.")
            }
            touch()
            updatePresentation()
        }
    }
    func prepareRestart() {
        guard restartReviewed, canRestart, restartOutcome == .accepted || restartOutcome == .uncertain else { return }
        restartOutcome = .idle
        restartReviewed = false
        restartError = nil
    }
    func copyCommand() {
        guard !connectionCommand.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionCommand, forType: .string)
        ToastCenter.shared.success(consoleText("连接命令已复制", "Connection command copied"))
        touch()
        focusCanvas()
    }
    func toggleDetails() { detailsOpen.toggle(); touch(); if !detailsOpen { focusCanvas() } }
    func toggleFullscreen() { canvas.webView?.window?.toggleFullScreen(nil); touch() }
    func syncFullscreen() { isFullscreen = canvas.webView?.window?.styleMask.contains(.fullScreen) == true }
    func focusCanvas() { if canInput { canvas.send(["kind": "focus", "epoch": epoch]) } }

    private func appendLog(_ value: String) { appendOutput(value + "\n") }
    private func appendOutput(_ value: String) {
        pendingLog += value
        if pendingLog.utf16.count > 65536 { pendingLog = boundedTail(pendingLog); outputTruncated = true }
        guard logFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flushLogs() }
        logFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    private func boundedTail(_ text: String) -> String {
        var units = Array(text.utf16.suffix(65536))
        if let first = units.first, (0xdc00...0xdfff).contains(first) { units.removeFirst() }
        return String(decoding: units, as: UTF16.self)
    }
    private func flushLogs() {
        logFlush?.cancel()
        logFlush = nil
        guard !pendingLog.isEmpty else { return }
        var next = logText + pendingLog
        pendingLog = ""
        if next.utf16.count > 65536 { next = boundedTail(next); outputTruncated = true }
        let lines = next.components(separatedBy: "\n")
        if lines.count > 2000 { next = lines.suffix(2000).joined(separator: "\n"); outputTruncated = true }
        logText = next
    }

    func canLeave() -> Bool {
        if busy { ToastCenter.shared.error(consoleText("请等待当前操作完成。", "Wait for the current operation to finish.")); return false }
        guard hasSession else { return true }
        canvas.send(["kind": "presentation", "epoch": epoch, "scale": fitScreen, "viewOnly": viewOnly, "active": false])
        let allowed = AppAlert.confirm(title: consoleText("断开控制台并离开", "Disconnect and leave"),
                                       message: consoleText("本地控制台连接将断开；已提交的云端操作不会撤销。", "The local console will disconnect. Submitted cloud operations will continue."))
        if !allowed { updatePresentation() }
        return allowed
    }

    func teardown() {
        guard active else { return }
        active = false
        metadataVersion += 1
        prepareID = nil
        preparingClient = false
        release(.closed)
        if let monitor = activityMonitor { NSEvent.removeMonitor(monitor) }
        activityMonitor = nil
        canvas.onEvent = nil
        context = nil
        modal = nil
        textDraft = ""
        clearCredentials()
        connectionCommand = ""
        connectionID = ""
        pendingLog = ""
        logText = ""
    }
    /// 一键安装 websockify（oci-start-mac 本机优先用 Process 安装；连远程后端时走服务端 API）
    func installWebsockify() {
        guard !busy else { return }
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
                if hasSession { release(.closed) }
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


}

// Only the RFB protocol canvas lives in WebKit. Native SwiftUI owns all controls and dialogs.
final class ConsoleCanvasBridge {
    let pageID = UUID().uuidString
    weak var webView: WKWebView?
    var onEvent: (([String: Any]) -> Void)?

    func send(_ command: [String: Any], completion: ((Bool) -> Void)? = nil) {
        guard let view = webView else { completion?(false); return }
        var payload = command
        payload["pageID"] = pageID
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { completion?(false); return }
        view.evaluateJavaScript("window.__nativeConsole ? window.__nativeConsole.receive(\(json)) : false") { value, error in
            completion?(error == nil && value as? Bool == true)
        }
    }
    func receive(_ event: [String: Any]) {
        guard event["pageID"] as? String == pageID else { return }
        onEvent?(event)
    }
    func dispose() {
        webView?.evaluateJavaScript("if(window.__nativeConsole) window.__nativeConsole.dispose()", completionHandler: nil)
        webView?.stopLoading()
        webView = nil
    }
}

enum InstanceNoVNCHTML {
    static func page(pageID: String) -> String {
        let encoded = (try? JSONSerialization.data(withJSONObject: pageID, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
        let id = String(data: encoded, encoding: .utf8) ?? "\"\""
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        html,body,#screen { margin:0;width:100%;height:100%;overflow:hidden;background:transparent }
        #screen { position:absolute;inset:0; }
        .mount { width:100%;height:100%;overflow:auto; }
        canvas { outline:none; }
        </style></head><body><div id="screen" role="application" aria-label="Remote VNC screen"></div>
        <script>
        (() => {
          'use strict';
          const pageID = \(id), host = document.getElementById('screen');
          const moduleURL = 'https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/core/rfb.js';
          let runtime, client, mount, epoch = '', disposed = false, connected = false;
          let awaitingCredentials = false, listeners = [], textJob, textFrame = 0;
          let options = { scale:false, viewOnly:false, active:true }, activityAt = 0, idleDeadline = 0;
          function post(kind, fields = {}) {
            if (disposed) return;
            window.webkit.messageHandlers.vnc.postMessage({ pageID, epoch, kind, ...fields });
          }
          function loadRuntime() {
            if (runtime) return runtime;
            let timer;
            const imported = import(moduleURL).then(mod => {
              const C = mod.default, methods = ['disconnect','focus','blur','sendCredentials','sendCtrlAltDel','sendKey','clipboardPasteFrom'];
              if (typeof C !== 'function' || methods.some(method => typeof C.prototype[method] !== 'function')) throw Error('runtime');
              return C;
            });
            runtime = Promise.race([imported, new Promise((_, reject) => {
              timer = setTimeout(() => reject(Error('timeout')), 30000);
            })]).catch(error => { runtime = undefined; throw error; }).finally(() => clearTimeout(timer));
            return runtime;
          }
          function canInput() { return !disposed && connected && client && options.active && !options.viewOnly && !textJob; }
          function activity() {
            if (!connected || Date.now() - activityAt < 250) return;
            activityAt = Date.now(); post('activity');
          }
          function finishText(sent) {
            const job = textJob;
            if (!job) return;
            textJob = undefined;
            if (textFrame) cancelAnimationFrame(textFrame);
            textFrame = 0;
            post('textFinished', { requestID:job.id, sent });
          }
          function disconnect() {
            finishText(false);
            connected = awaitingCredentials = false;
            const previous = client, previousMount = mount;
            client = mount = undefined;
            if (previous) {
              for (const pair of listeners) previous.removeEventListener(pair[0], pair[1]);
              listeners = [];
              try { previous.disconnect(); } catch (_) {}
            }
            if (previousMount) previousMount.remove();
          }
          function presentation() {
            if (!client) return;
            if (options.viewOnly) finishText(false);
            if (!options.active || options.viewOnly) { try { client.blur(); } catch (_) {} }
            client.resizeSession = false;
            client.scaleViewport = options.scale;
            client.viewOnly = options.viewOnly || !options.active;
            client.focusOnClick = options.active && !options.viewOnly;
            client.background = getComputedStyle(document.body).backgroundColor;
            if (canInput()) { try { client.focus(); } catch (_) {} }
          }
          function fit() { if (client) client.scaleViewport = options.scale; }
          function focus() { if (canInput()) client.focus(); }
          async function connect(command) {
            disconnect();
            epoch = command.epoch;
            const currentEpoch = epoch;
            options = { scale:command.scale === true, viewOnly:command.viewOnly === true, active:command.active === true };
            try {
              const url = new URL(command.url);
              if (!['ws:','wss:'].includes(url.protocol) || !url.hostname || url.username || url.password || url.hash ||
                  (location.protocol === 'https:' && url.protocol !== 'wss:')) throw Error('url');
              const C = await loadRuntime();
              if (disposed || currentEpoch !== epoch) return;
              const target = document.createElement('div');
              target.className = 'mount'; host.append(target); mount = target;
              const current = new C(target, command.url, { shared:true, wsProtocols:['binary'] });
              client = current;
              const currentConnection = () => !disposed && epoch === currentEpoch && client === current;
              const listen = (name, callback) => {
                const listener = event => { if (currentConnection()) callback(event.detail || {}); };
                listeners.push([name,listener]); current.addEventListener(name,listener);
              };
              listen('connect', () => {
                connected = true; idleDeadline = Date.now() + 1800000; awaitingCredentials = false; presentation();
                const canvas = target.querySelector('canvas');
                if (canvas) canvas.setAttribute('aria-label', 'Remote VNC screen');
                post('connected'); focus();
              });
              listen('disconnect', detail => {
                disconnect(); post('disconnected', { clean:detail.clean === true, reason:typeof detail.reason === 'string' ? detail.reason : '' });
              });
              listen('credentialsrequired', detail => {
                awaitingCredentials = true;
                post('credentials', { types:Array.isArray(detail.types) ? detail.types.filter(type => typeof type === 'string') : [] });
              });
              listen('securityfailure', detail => {
                disconnect(); post('securityFailure', { reason:typeof detail.reason === 'string' ? detail.reason : '' });
              });
              listen('desktopname', detail => { if (typeof detail.name === 'string') post('desktopName', { name:detail.name }); });
              // No automatic clipboard sync: Web's visible "Send text" operation emits keystrokes.
              current.resizeSession = false;
              presentation();
            } catch (_) { if (!disposed && epoch === currentEpoch) { disconnect(); post('rendererError'); } }
          }
          function textKeysyms(text) {
            const result = []; let afterReturn = false;
            for (const character of text) {
              const point = character.codePointAt(0);
              if (point === 10 && afterReturn) { afterReturn = false; continue; }
              afterReturn = point === 13;
              if (point === 10 || point === 13) result.push(0xff0d);
              else if (point === 9) result.push(0xff09);
              else if (point === 8) result.push(0xff08);
              else if (point === 27) result.push(0xff1b);
              else if (point === 127) result.push(0xffff);
              else if (point < 32 || (point >= 0xd800 && point <= 0xdfff)) return null;
              else result.push(point <= 0xff ? point : 0x01000000 + point);
            }
            return result;
          }
          function sendText(command) {
            if (!client || !connected || options.viewOnly || textJob || typeof command.text !== 'string' ||
                command.text.length > 65536) return false;
            const keysyms = textKeysyms(command.text);
            if (!keysyms) { post('inputError'); return false; }
            const current = client, generation = epoch;
            const job = { id:command.requestID, offset:0 }; textJob = job;
            const batch = () => {
              textFrame = 0;
              if (textJob !== job) return;
              if (!connected || client !== current || epoch !== generation || options.viewOnly) { finishText(false); return; }
              try {
                const end = Math.min(job.offset + 64, keysyms.length);
                // The native text dialog pauses physical input; explicit text keys are its only input.
                const previousViewOnly = current.viewOnly;
                current.viewOnly = false;
                try {
                  while (job.offset < end) {
                    const keysym = keysyms[job.offset++];
                    try { current.sendKey(keysym, undefined, true); }
                    finally { current.sendKey(keysym, undefined, false); }
                  }
                } finally { current.viewOnly = previousViewOnly; }
                activity();
              } catch (_) { finishText(false); post('inputError'); return; }
              if (job.offset === keysyms.length) finishText(true);
              else textFrame = requestAnimationFrame(batch);
            };
            textFrame = requestAnimationFrame(batch);
            return true;
          }
          window.__nativeConsole = {
            receive(command) {
              if (disposed || command.pageID !== pageID) return false;
              if (command.kind === 'prepare') {
                const requestID = command.requestID;
                loadRuntime().then(() => post('runtimeReady',{requestID})).catch(() => post('runtimeError',{requestID}));
                return true;
              }
              if (command.kind === 'theme') {
                document.body.style.backgroundColor = command.background;
                if (client) client.background = command.background;
                return true;
              }
              if (command.kind === 'connect') { connect(command); return true; }
              if (command.epoch !== epoch) return false;
              try {
                switch (command.kind) {
                  case 'disconnect': disconnect(); epoch = ''; return true;
                  case 'presentation':
                    options = { scale:command.scale === true, viewOnly:command.viewOnly === true, active:command.active === true };
                    presentation(); return true;
                  case 'focus': focus(); return true;
                  case 'touch': idleDeadline = command.deadline; return true;
                  case 'credentials':
                    if (!client || !awaitingCredentials) return false;
                    awaitingCredentials = false; client.sendCredentials(command.values); return true;
                  case 'ctrlAltDel':
                    if (!canInput()) return false;
                    client.sendCtrlAltDel(); activity(); return true;
                  case 'text': return sendText(command);
                  case 'cancelText': finishText(false); return true;
                  default: return false;
                }
              } catch (_) { post('inputError'); return false; }
            },
            dispose() {
              disconnect(); disposed = true; epoch = '';
              resize.disconnect();
              window.removeEventListener('resize', fit);
            }
          };
          const resize = new ResizeObserver(fit); resize.observe(host);
          window.addEventListener('resize',fit);
          for (const name of ['pointerdown','pointermove','keydown','wheel']) host.addEventListener(name, event => {
            if (connected && idleDeadline && Date.now() >= idleDeadline) {
              event.preventDefault(); event.stopImmediatePropagation();
              post('idleExpired'); disconnect(); return;
            }
            activity();
          }, {capture:true});
          window.addEventListener('pagehide', () => window.__nativeConsole.dispose(), {once:true});
          post('bridgeReady');
        })();
        </script></body></html>
        """
    }
}

struct NoVNCCanvas: NSViewRepresentable {
    let bridge: ConsoleCanvasBridge
    let baseURL: String
    let background: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "vnc")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        bridge.webView = view
        let base = URL(string: baseURL)
        let cookies = base.map { HTTPCookieStorage.shared.cookies(for: $0) ?? [] } ?? []
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            config.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            guard bridge.webView === view else { return }
            view.loadHTMLString(InstanceNoVNCHTML.page(pageID: bridge.pageID), baseURL: base)
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.background = "#" + background
        bridge.send(["kind": "theme", "background": context.coordinator.background])
    }
    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge, background: "#" + background) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.bridge.dispose()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "vnc")
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let bridge: ConsoleCanvasBridge
        var background: String
        init(bridge: ConsoleCanvasBridge, background: String) { self.bridge = bridge; self.background = background }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let event = message.body as? [String: Any] else { return }
            if event["kind"] as? String == "bridgeReady" { bridge.send(["kind": "theme", "background": background]) }
            bridge.receive(event)
        }
        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            bridge.onEvent?(["kind": "bridgeError"])
        }
        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            bridge.onEvent?(["kind": "bridgeError"])
        }
        func webView(_ view: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

/// Selectable diagnostics with optional following; never a substitute for the remote canvas.
private struct ConsoleDiagnosticText: NSViewRepresentable {
    let text: String
    let dark: Bool
    let follow: Bool
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 12, height: 10)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.frame.size.width = scroll.contentSize.width
        view.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        view.textColor = dark ? NSColor(calibratedWhite: 0.82, alpha: 1) : .black
        if view.string != text {
            view.string = text
            if follow { view.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0)) }
        } else if follow != context.coordinator.follow, follow {
            view.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.follow = follow
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var follow = true }
}

struct InstanceConsoleView: View {
    let item: InstanceItem
    var onBack: (() -> Void)?
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: NavigationState
    @AppStorage("appLocale") private var locale = "zh_CN"
    @State private var leaveGuardOwner = UUID()
    @StateObject private var model: InstanceConsoleViewModel

    init(item: InstanceItem, onBack: (() -> Void)? = nil) {
        self.item = item
        self.onBack = onBack
        _model = StateObject(wrappedValue: InstanceConsoleViewModel(item: item))
    }
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                notices
                tools
                stage
                footer
            }
            .disabled(model.modal != nil)
            if let modal = model.modal {
                Color.black.opacity(0.28).ignoresSafeArea()
                modalContent(modal)
            }
        }
        .font(.system(size: 14))
        .foregroundColor(AppTheme.textPrimary(dark))
        .background(AppTheme.pageBg(dark))
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
            navigation.setLeaveGuard(owner: leaveGuardOwner) { model.canLeave() }
        }
        .onDisappear {
            navigation.removeLeaveGuard(owner: leaveGuardOwner)
            model.teardown()
        }
        .onChange(of: model.fitScreen) { _ in model.updatePresentation() }
        .onChange(of: model.viewOnly) { _ in model.updatePresentation() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in model.syncFullscreen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in model.syncFullscreen() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.checkIdle() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if onBack != nil {
                AppButton(title: consoleText("返回", "Back"), systemImage: "chevron.left", kind: .secondary) {
                    guard model.canLeave() else { return }
                    model.teardown()
                    onBack?()
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.instanceLabel.isEmpty ? item.id : model.instanceLabel)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    .help(model.instanceLabel)
                if !model.instanceIP.isEmpty {
                    Text(model.instanceIP).font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1)
                }
            }
            StatusBadge(text: model.statusText, tone: model.isConnected ? .success : (model.phase == .error ? .danger : .info))
            Spacer(minLength: 8)
            AppButton(title: consoleText("重新引导", "Restart"), systemImage: "arrow.clockwise", kind: .danger) { model.requestRestart() }
                .disabled(!model.canRestart)
            if model.hasSession {
                AppButton(title: model.isConnecting ? consoleText("取消连接", "Cancel connection") : consoleText("断开", "Disconnect"), kind: .secondary) {
                    model.disconnect()
                }.disabled(model.busy)
            }
            AppButton(title: model.hasSession ? consoleText("重新创建", "Recreate") : consoleText("创建控制台", "Create console"),
                      systemImage: "plus", kind: .primary, isLoading: model.preparingClient) { model.requestCreate() }
                .disabled(!model.canCreate)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(AppTheme.cardBg(dark))
        .overlay(Divider(), alignment: .bottom)
    }

    private var notices: some View {
        VStack(spacing: 0) {
            if model.metadataLoading {
                notice(consoleText("正在加载实例信息…", "Loading instance information…"), error: false)
            }
            if let error = model.metadataError {
                HStack {
                    Text(error).font(.system(size: 13)).foregroundColor(AppTheme.danger)
                    Spacer()
                    AppButton(title: consoleText("重新加载", "Reload"), kind: .secondary) { model.reloadMetadata() }
                        .disabled(model.metadataLoading || model.hasSession || model.busy)
                }.padding(12)
            }
            if let error = model.errorText { notice(error, error: true) }
            if model.idleWarning {
                notice(consoleText("连接将在闲置满 30 分钟后断开，请操作画面以继续。", "This session will close after 30 minutes of inactivity. Interact to continue."), error: false)
            }
        }
    }

    private func notice(_ message: String, error: Bool) -> some View {
        Text(message).font(.system(size: 13))
            .foregroundColor(error ? AppTheme.danger : AppTheme.textSecondary(dark))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var tools: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                AppButton(title: consoleText("适应屏幕", "Fit"), kind: model.fitScreen ? .primary : .secondary) { model.fitScreen = true }
                AppButton(title: consoleText("原始大小", "Original size"), kind: !model.fitScreen ? .primary : .secondary) { model.fitScreen = false }
                Toggle(consoleText("只读", "View only"), isOn: $model.viewOnly)
                    .toggleStyle(CheckboxToggleStyle()).disabled(model.textPending)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                AppButton(title: "Ctrl + Alt + Del", kind: .secondary) { model.sendCtrlAltDel() }.disabled(!model.canInput)
                AppButton(title: consoleText("发送文本", "Send text"), systemImage: "keyboard", kind: .secondary) { model.openText() }
                    .disabled(!model.isConnected || model.viewOnly || model.busy)
                AppButton(title: consoleText("连接详情", "Details"), systemImage: "text.alignleft", kind: .secondary) { model.toggleDetails() }
                AppButton(title: "", systemImage: model.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", kind: .secondary) {
                    model.toggleFullscreen()
                }.help(model.isFullscreen ? consoleText("退出全屏", "Exit fullscreen") : consoleText("全屏", "Fullscreen"))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppTheme.cardBg(dark))
        .overlay(Divider(), alignment: .bottom)
    }

    private var stage: some View {
        HStack(spacing: 0) {
            ZStack {
                NoVNCCanvas(bridge: model.canvas, baseURL: session.serverURL, background: appearance.contentPalette.page)
                    .allowsHitTesting(model.modal == nil && !model.busy)
                if !model.isConnected {
                    VStack(spacing: 12) {
                        if model.isConnecting || model.preparingClient {
                            ProgressView().scaleEffect(0.85)
                            Text(model.statusText).font(.system(size: 13))
                        } else {
                            Image(systemName: "display").font(.system(size: 30, weight: .light))
                            Text(model.phase == .manual
                                 ? consoleText("代理尚未就绪，可在连接详情中查看手动连接命令。", "The display proxy is not ready. Open Details for the manual connection command.")
                                 : consoleText("创建控制台后，远程画面将在这里显示。", "Create a console to show the remote screen here."))
                                .font(.system(size: 13)).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundColor(AppTheme.textSecondary(dark)).padding(28)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.detailsOpen {
                details.frame(width: 330)
                    .overlay(Divider(), alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(consoleText("连接详情", "Connection details")).font(.system(size: 14, weight: .semibold))
                Spacer()
                AppButton(title: "", systemImage: "xmark", kind: .secondary) { model.toggleDetails() }
                    .help(consoleText("关闭详情", "Close details"))
            }.padding(12)
            Divider()
            if !model.connectionID.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(consoleText("连接 ID", "Connection ID")).font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
                    Text(model.connectionID).font(.system(size: 12, design: .monospaced)).lineLimit(2).help(model.connectionID)
                }.padding(12)
            }
            if !model.connectionCommand.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(consoleText("手动连接命令", "Manual connection command")).font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
                    ConsoleDiagnosticText(text: model.connectionCommand, dark: dark, follow: false).frame(height: 104)
                    AppButton(title: consoleText("复制命令", "Copy command"), systemImage: "doc.on.doc", kind: .secondary) { model.copyCommand() }
                }.padding(12)
            }
            if model.needsWebsockifyInstall || model.isInstallingWebsockify {
                AppButton(title: consoleText("安装 websockify", "Install websockify"), systemImage: "arrow.down.circle",
                          kind: .secondary, isLoading: model.isInstallingWebsockify) { model.installWebsockify() }
                    .disabled(model.busy).padding(12)
            }
            HStack {
                Text(consoleText("连接日志", "Connection log")).font(.system(size: 13))
                Spacer()
                Toggle(consoleText("跟随输出", "Follow"), isOn: $model.followOutput)
                    .toggleStyle(CheckboxToggleStyle()).font(.system(size: 12))
            }.padding(12)
            if model.outputTruncated {
                Text(consoleText("较早的日志已截断。", "Older output was truncated."))
                    .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark)).padding(.horizontal, 12)
            }
            ConsoleDiagnosticText(text: model.logText.isEmpty ? consoleText("暂无日志", "No output yet") : model.logText, dark: dark, follow: model.followOutput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(AppTheme.cardBg(dark))
    }

    private var footer: some View {
        HStack {
            Text(model.desktopName.isEmpty ? consoleText("点击画面后可使用键盘与鼠标。", "Click the screen to use the keyboard and mouse.") : model.desktopName)
                .lineLimit(1).help(model.desktopName)
            Spacer(minLength: 12)
            Text(model.isConnected
                 ? consoleText("闲置断开倒计时 \(model.idleTime)", "Idle timeout in \(model.idleTime)")
                 : consoleText("断开本地通道不会撤销云端操作。", "Disconnecting does not undo cloud operations."))
                .foregroundColor(model.idleWarning ? AppTheme.danger : AppTheme.textSecondary(dark))
        }
        .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(AppTheme.cardBg(dark)).overlay(Divider(), alignment: .top)
    }

    @ViewBuilder
    private func modalContent(_ modal: ConsoleModal) -> some View {
        switch modal {
        case .create: createDialog
        case .credentials: credentialsDialog
        case .text: textDialog
        case .restart: restartDialog
        }
    }

    private func dialog<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 18, weight: .semibold))
            content()
        }
        .padding(24).frame(width: 520)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border(dark), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
        .onExitCommand { model.closeModal() }
    }

    private var createDialog: some View {
        dialog(model.hasSession ? consoleText("重新创建控制台", "Recreate console") : consoleText("创建控制台", "Create console")) {
            Text(consoleText("为 \(model.instanceLabel) 创建 VNC 控制台连接？", "Create a VNC console for \(model.instanceLabel)?"))
            Text(consoleText("此操作会替换该实例现有的活动云控制台连接。客户端引擎加载成功后才会提交创建请求。", "This replaces the instance's active cloud console connection. Creation starts after the client has loaded."))
                .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
            if let error = model.errorText { Text(error).font(.system(size: 13)).foregroundColor(AppTheme.danger) }
            HStack {
                Spacer()
                AppButton(title: consoleText("取消", "Cancel"), kind: .secondary) { model.closeModal() }.disabled(model.preparingClient)
                AppButton(title: consoleText("确认创建", "Create"), kind: .primary, isLoading: model.preparingClient) { model.createConnection() }
                    .disabled(!model.canCreate)
            }
        }
    }

    private var credentialsDialog: some View {
        dialog(consoleText("VNC 认证", "VNC authentication")) {
            if model.credentialTypes.contains("username") {
                input(consoleText("用户名", "Username"), text: $model.credentialUsername)
            }
            if model.credentialTypes.contains("target") {
                input(consoleText("目标", "Target"), text: $model.credentialTarget)
            }
            if model.credentialTypes.contains("password") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(consoleText("密码", "Password")).font(.system(size: 13))
                    SecureField("", text: $model.credentialPassword).textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            Text(consoleText("凭据仅用于当前 VNC 连接，提交或取消后会清除。", "Credentials are used only for this VNC connection and cleared after submission or cancellation."))
                .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
            HStack {
                Spacer()
                AppButton(title: consoleText("取消连接", "Cancel connection"), kind: .secondary) { model.closeModal() }
                AppButton(title: consoleText("认证", "Authenticate"), kind: .primary) { model.submitCredentials() }
            }
        }
    }

    private func input(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13))
            TextField("", text: text).textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private var textDialog: some View {
        dialog(consoleText("发送文本", "Send text")) {
            Text(consoleText("要键入的文本", "Text to type")).font(.system(size: 13))
            TextEditor(text: $model.textDraft)
                .font(.system(size: 14, design: .monospaced))
                .frame(height: 170)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border(dark), lineWidth: 1))
                .disabled(model.textPending || model.textOutcome != .idle)
            Text(consoleText("文本会逐字作为键盘输入发送，换行可能执行命令。取消无法撤销已经发送的内容；最多 65,536 个 UTF-16 单元。", "Text is sent as keystrokes. Newlines may execute commands. Cancellation cannot undo sent characters. Limit: 65,536 UTF-16 units."))
                .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
            if model.textOutcome != .idle {
                Text(model.textOutcome == .sent
                     ? consoleText("按键已发送，请核对远程画面。", "Keystrokes sent. Verify the remote screen.")
                     : consoleText("发送已中断，部分内容可能已到达远端；核对后再发送新文本。", "Sending was interrupted. Some text may have arrived; review before sending new text."))
                    .font(.system(size: 13))
            }
            if let error = model.textError { Text(error).font(.system(size: 13)).foregroundColor(AppTheme.danger) }
            HStack {
                if model.textOutcome == .idle && !model.textPending {
                    AppButton(title: consoleText("粘贴到输入框", "Paste into field"), systemImage: "doc.on.clipboard", kind: .secondary) { model.pasteLocalText() }
                }
                Spacer()
                if model.textPending {
                    AppButton(title: consoleText("取消发送", "Cancel sending"), kind: .secondary) { model.cancelText() }
                } else {
                    AppButton(title: consoleText("关闭", "Close"), kind: .secondary) { model.closeModal() }
                    if model.textOutcome != .idle {
                        AppButton(title: consoleText("新文本", "New text"), kind: .secondary) { model.newText() }
                    } else {
                        AppButton(title: consoleText("发送", "Send"), kind: .primary) { model.sendText() }
                            .disabled(!model.isConnected || model.viewOnly || model.textDraft.isEmpty)
                    }
                }
            }
        }
    }

    private var restartDialog: some View {
        dialog(consoleText("重新引导", "Restart")) {
            Text(restartMessage).font(.system(size: 14))
            if let error = model.restartError { Text(error).font(.system(size: 13)).foregroundColor(AppTheme.danger) }
            if model.restartOutcome == .accepted || model.restartOutcome == .uncertain {
                Toggle(consoleText("我已核对当前实例状态", "I have reviewed the current instance state"), isOn: $model.restartReviewed)
                    .toggleStyle(CheckboxToggleStyle()).font(.system(size: 13))
            }
            HStack {
                Spacer()
                AppButton(title: consoleText("关闭", "Close"), kind: .secondary) { model.closeModal() }.disabled(model.isRebooting)
                if model.restartOutcome == .accepted || model.restartOutcome == .uncertain {
                    AppButton(title: consoleText("准备再次重引导", "Prepare another restart"), kind: .secondary) { model.prepareRestart() }
                        .disabled(!model.restartReviewed || !model.canRestart)
                } else {
                    AppButton(title: consoleText("确认重引导", "Confirm restart"), kind: .danger, isLoading: model.isRebooting) { model.reboot() }
                        .disabled(!model.canRestart)
                }
            }
        }
    }

    private var restartMessage: String {
        switch model.restartOutcome {
        case .idle, .failed:
            return consoleText("对 \(model.instanceLabel) 提交 RESET 重引导？实例会被重启。", "Submit a RESET restart for \(model.instanceLabel)? This restarts the instance.")
        case .sending:
            return consoleText("正在提交，请等待回执。", "Submitting. Wait for the acknowledgement.")
        case .accepted:
            return consoleText("请求已被接受，仅代表提交成功；请核对实例实际状态。", "The request was accepted. This confirms submission; review the actual instance state.")
        case .uncertain:
            return consoleText("请求结果未知，可能已经提交。请先核对，勿直接重复操作。", "The result is unknown and may have been submitted. Review before another operation.")
        }
    }
}
