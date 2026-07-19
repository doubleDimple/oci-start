import SwiftUI
import AppKit

// MARK: - Service

struct InstanceSSHService {
    let baseURL: String
    private let client = APIClient.shared

    struct SSHConfig {
        var username: String = "root"
        var host: String = ""
        var port: String = "22"
        var password: String = ""
    }

    func loadConfig(localId: String) async throws -> SSHConfig {
        let url = try client.makeURL(baseURL, path: "/oci/ssh/config/\(localId)")
        let raw = try await client.getJSON(url)
        guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return SSHConfig()
        }
        let ok = (obj["success"] as? Bool) ?? false
        guard ok, let data = obj["data"] as? [String: Any] else {
            return SSHConfig()
        }
        var c = SSHConfig()
        c.username = InstanceJSON.string(data["username"]).isEmpty ? "root" : InstanceJSON.string(data["username"])
        c.host = InstanceJSON.string(data["host"])
        let p = InstanceJSON.string(data["port"])
        c.port = p.isEmpty ? "22" : p
        c.password = InstanceJSON.string(data["sshPassword"])
        if c.password.isEmpty {
            c.password = InstanceJSON.string(data["password"])
        }
        return c
    }

    func saveConfig(localId: String, username: String, port: String, password: String) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/ssh/config")
        let raw = try await client.postJSON(url, body: [
            "instanceId": localId,
            "username": username,
            "port": port,
            "password": password
        ])
        let r = InstanceJSON.successMessage(raw, fallback: "SSH 配置已保存")
        if !r.ok { throw APIError.serverMessage(r.message) }
    }

    /// POST `/oci/sftp/upload` multipart
    func sftpUpload(
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String,
        fileURL: URL
    ) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/sftp/upload")
        let raw = try await client.postMultipart(
            url,
            fields: [
                "host": host,
                "port": "\(port)",
                "username": username,
                "password": password,
                "remotePath": remotePath
            ],
            fileFieldName: "file",
            fileURL: fileURL
        )
        if let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            let ok = (obj["success"] as? Bool) ?? false
            let msg = InstanceJSON.string(obj["message"])
            let dataMsg = InstanceJSON.string(obj["data"])
            if !ok {
                throw APIError.serverMessage(msg.isEmpty ? "上传失败" : msg)
            }
            return dataMsg.isEmpty ? (msg.isEmpty ? remotePath : msg) : dataMsg
        }
        return remotePath
    }

    /// POST `/oci/sftp/download` → binary file
    func sftpDownload(
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String
    ) async throws -> (Data, String) {
        let url = try client.makeURL(baseURL, path: "/oci/sftp/download")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "host": host,
            "port": port,
            "username": username,
            "password": password,
            "remotePath": remotePath
        ])
        let (data, http) = try await client.data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.serverMessage(msg.isEmpty ? "下载失败" : msg)
        }
        var name = remotePath.split(separator: "/").last.map(String.init) ?? "download"
        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let r = cd.range(of: "filename\\*=UTF-8''([^;]+)", options: .regularExpression) {
                let raw = String(cd[r]).replacingOccurrences(of: "filename*=UTF-8''", with: "")
                name = raw.removingPercentEncoding ?? raw
            } else if let r = cd.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
                name = String(cd[r])
                    .replacingOccurrences(of: "filename=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
        }
        return (data, name)
    }
}

// MARK: - ViewModel

@MainActor
final class InstanceSSHViewModel: ObservableObject {
    let item: InstanceItem
    private let session: AppSession
    private let service: InstanceSSHService
    private let ws = NativeWSClient()

    @Published var username = "root"
    @Published var host = ""
    @Published var port = "22"
    @Published var password = ""
    @Published var showPassword = false
    @Published var output = ""
    @Published var statusText = "未连接"
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isBusy = false
    @Published var isTransferring = false
    @Published var transferProgress: Double = 0
    @Published var errorText: String?
    @Published var fontSize: CGFloat = 14
    @Published var themeKey: String = "matrix"
    @Published var termCols: Int = 80
    @Published var termRows: Int = 24
    @Published var showSearch = false
    @Published var searchQuery = ""
    @Published var searchHitText = ""

    private var lastResizeSent = (0, 0)

    var themeOptions: [SelectOption] {
        [
            SelectOption(id: "matrix", title: "Matrix"),
            SelectOption(id: "tokyonight", title: "Tokyo Night"),
            SelectOption(id: "dracula", title: "Dracula"),
            SelectOption(id: "nord", title: "Nord"),
            SelectOption(id: "monokai", title: "Monokai"),
            SelectOption(id: "solarizedLight", title: "Solarized Light"),
            SelectOption(id: "highContrast", title: "High Contrast")
        ]
    }

    var terminalTheme: TerminalTheme { TerminalTheme.named(themeKey) }

    init(item: InstanceItem, session: AppSession = .shared) {
        self.item = item
        self.session = session
        self.service = InstanceSSHService(baseURL: session.serverURL)
        self.host = item.publicIps
        if let saved = UserDefaults.standard.object(forKey: "terminal.fontSize") as? Double {
            fontSize = CGFloat(max(10, min(24, saved)))
        }
        if let th = UserDefaults.standard.string(forKey: "terminal.theme"), !th.isEmpty {
            themeKey = th
        }
        wireWS()
    }

    private func wireWS() {
        ws.onState = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .idle:
                break
            case .connecting:
                self.isConnecting = true
                self.statusText = "连接中…"
            case .open:
                break
            case .closed(let reason):
                if self.isConnected || self.isConnecting {
                    self.isConnected = false
                    self.isConnecting = false
                    self.statusText = reason.map { "已断开：\($0)" } ?? "已断开"
                }
            }
        }
        ws.onText = { [weak self] text in
            self?.handleWSText(text)
        }
    }

    private func handleWSText(_ text: String) {
        // 服务端多为裸文本；兼容 JSON {type,data/message}
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            if type == "output" {
                let d = InstanceJSON.string(obj["data"])
                if !d.isEmpty { append(d) }
            } else if type == "error" {
                let msg = InstanceJSON.string(obj["message"])
                append("\r\n\u{001B}[31m\(msg.isEmpty ? "错误" : msg)\u{001B}[0m\r\n")
                disconnect(userInitiated: false)
                return
            } else {
                append(text)
            }
        } else {
            append(text)
        }

        if !isConnected {
            if text.contains("SSH conn success") || text.contains("✅") {
                isConnected = true
                isConnecting = false
                statusText = "已连接 \(username)@\(host)"
                // 连接后同步终端尺寸
                sendResize(cols: termCols, rows: termRows, force: true)
            } else if text.contains("SSH conn error") || text.contains("❌") {
                isConnecting = false
                isConnected = false
                statusText = "连接失败"
            } else {
                // 任意输出也视为已连通（对齐 Web：首包后 connected=true）
                isConnected = true
                isConnecting = false
                statusText = "已连接 \(username)@\(host)"
                sendResize(cols: termCols, rows: termRows, force: true)
            }
        }
    }

    func start() {
        append("欢迎使用 OCI-Start SSH 终端\r\n\r\n")
        Task { await loadConfig() }
    }

    func loadConfig() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let c = try await service.loadConfig(localId: item.id)
            if !c.username.isEmpty { username = c.username }
            if !c.host.isEmpty { host = c.host }
            else if host.isEmpty { host = item.publicIps }
            if !c.port.isEmpty { port = c.port }
            if !c.password.isEmpty { password = c.password }
        } catch {
            if host.isEmpty { host = item.publicIps }
        }
    }

    func connect() {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !h.isEmpty, !p.isEmpty, !password.isEmpty else {
            errorText = "请填写用户名、地址、端口和密码"
            append("\r\n\u{001B}[31m请填写完整的连接信息\u{001B}[0m\r\n")
            return
        }
        guard let portNum = Int(p), portNum > 0, portNum <= 65535 else {
            errorText = "端口无效"
            return
        }
        errorText = nil
        isConnecting = true
        statusText = "连接中…"
        append("\r\n▶ 正在连接 \(u)@\(h):\(p) …\r\n")

        do {
            let url = try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/ssh")
            ws.connect(url: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                self.ws.sendJSON([
                    "type": "connect",
                    "data": [
                        "host": h,
                        "port": portNum,
                        "username": u,
                        "password": self.password
                    ]
                ])
            }
        } catch {
            isConnecting = false
            errorText = error.localizedDescription
            statusText = "连接失败"
        }
    }

    func disconnect(userInitiated: Bool = true) {
        ws.disconnect(reason: nil)
        isConnected = false
        isConnecting = false
        statusText = "已断开"
        if userInitiated {
            append("\r\n\u{001B}[33m● 连接已断开\u{001B}[0m\r\n")
        }
    }

    func reconnect() {
        disconnect(userInitiated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.connect()
        }
    }

    func sendInput(_ text: String) {
        guard isConnected else { return }
        ws.sendJSON(["type": "input", "data": text])
    }

    func onTerminalResize(cols: Int, rows: Int) {
        termCols = cols
        termRows = rows
        sendResize(cols: cols, rows: rows, force: false)
    }

    private func sendResize(cols: Int, rows: Int, force: Bool) {
        guard isConnected else { return }
        if !force, lastResizeSent == (cols, rows) { return }
        lastResizeSent = (cols, rows)
        ws.sendJSON([
            "type": "resize",
            "data": ["cols": cols, "rows": rows]
        ])
    }

    func saveConfig() {
        Task {
            isBusy = true
            do {
                try await service.saveConfig(
                    localId: item.id,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: port.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                ToastCenter.shared.success("SSH 配置已保存")
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    func copyPassword() {
        let p = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            ToastCenter.shared.error("密码为空")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(p, forType: .string)
        ToastCenter.shared.success("密码已复制")
    }

    func copySSHCommand() {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !h.isEmpty else {
            ToastCenter.shared.error("请先填写主机和用户名")
            return
        }
        var cmd = "ssh \(u)@\(h)"
        if p != "22" && !p.isEmpty { cmd += " -p \(p)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        ToastCenter.shared.success("已复制：\(cmd)")
    }

    func clearOutput() {
        output = ""
        searchHitText = ""
    }

    func downloadLog() {
        let plain = TerminalANSI.plainForLog(output)
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastCenter.shared.error("暂无终端输出内容")
            return
        }
        let hostPart = host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "terminal" : host
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "ssh-\(hostPart)-\(df.string(from: Date())).txt"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedFileTypes = ["txt"]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try plain.data(using: .utf8)?.write(to: url)
            ToastCenter.shared.success("日志已保存")
            append("\r\n\u{001B}[32m✅ 日志已下载\u{001B}[0m\r\n")
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func changeFont(_ delta: CGFloat) {
        fontSize = max(10, min(24, fontSize + delta))
        UserDefaults.standard.set(Double(fontSize), forKey: "terminal.fontSize")
    }

    func setTheme(_ key: String) {
        themeKey = key
        UserDefaults.standard.set(key, forKey: "terminal.theme")
    }

    // MARK: - SFTP

    func uploadFile() {
        guard isConnected else {
            append("\r\n\u{001B}[31m请先建立 SSH 连接\u{001B}[0m\r\n")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择要上传到服务器的文件"
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPath = u.isEmpty ? "/root/" : "/home/\(u)/"
        guard let remote = AppAlert.prompt(
            title: "上传文件",
            message: "文件：\(fileURL.lastPathComponent)\n请输入远程目录或完整路径",
            defaultValue: defaultPath,
            placeholder: defaultPath,
            confirmTitle: "上传"
        ) else { return }
        let remotePath = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remotePath.isEmpty else {
            ToastCenter.shared.error("请输入远程路径")
            return
        }

        Task { await performUpload(fileURL: fileURL, remotePath: remotePath) }
    }

    private func performUpload(fileURL: URL, remotePath: String) async {
        guard let portNum = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            ToastCenter.shared.error("端口无效")
            return
        }
        isTransferring = true
        transferProgress = 0.1
        append("\r\n\u{001B}[33m▶ 正在上传 \(fileURL.lastPathComponent) …\u{001B}[0m\r\n")
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.sftpUpload(
                    host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: portNum,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    remotePath: remotePath,
                    fileURL: fileURL
                )
            }
            transferProgress = 1
            append("\r\n\u{001B}[32m✅ 上传成功: \(msg)\u{001B}[0m\r\n")
            ToastCenter.shared.success("上传成功")
        } catch {
            append("\r\n\u{001B}[31m❌ 上传失败: \(error.localizedDescription)\u{001B}[0m\r\n")
            ToastCenter.shared.error(error.localizedDescription)
        }
        isTransferring = false
        transferProgress = 0
    }

    func downloadFile() {
        guard isConnected else {
            append("\r\n\u{001B}[31m请先建立 SSH 连接\u{001B}[0m\r\n")
            return
        }
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = u.isEmpty ? "/root/file.txt" : "/home/\(u)/file.txt"
        guard let remote = AppAlert.prompt(
            title: "下载文件",
            message: "请输入远程文件完整路径",
            defaultValue: hint,
            placeholder: hint,
            confirmTitle: "下载"
        ) else { return }
        let remotePath = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remotePath.isEmpty else {
            ToastCenter.shared.error("请输入远程文件路径")
            return
        }
        Task { await performDownload(remotePath: remotePath) }
    }

    private func performDownload(remotePath: String) async {
        guard let portNum = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            ToastCenter.shared.error("端口无效")
            return
        }
        isTransferring = true
        append("\r\n\u{001B}[33m▶ 正在下载 \(remotePath) …\u{001B}[0m\r\n")
        do {
            let result = try await LoadingHUD.shared.during {
                try await service.sftpDownload(
                    host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: portNum,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    remotePath: remotePath
                )
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = result.1
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try result.0.write(to: url)
                append("\r\n\u{001B}[32m✅ 下载成功: \(remotePath)\u{001B}[0m\r\n")
                ToastCenter.shared.success("下载成功")
            }
        } catch {
            append("\r\n\u{001B}[31m❌ 下载失败: \(error.localizedDescription)\u{001B}[0m\r\n")
            ToastCenter.shared.error(error.localizedDescription)
        }
        isTransferring = false
    }

    func updateSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchHitText = ""
            return
        }
        let plain = TerminalANSI.strip(output).lowercased()
        let needle = q.lowercased()
        var count = 0
        var range = plain.startIndex..<plain.endIndex
        while let r = plain.range(of: needle, options: [], range: range) {
            count += 1
            range = r.upperBound..<plain.endIndex
        }
        searchHitText = count == 0 ? "无结果" : "\(count) 处"
    }

    private func append(_ s: String) {
        output += s
        if output.count > 400_000 {
            output = String(output.suffix(300_000))
        }
    }

    func teardown() {
        ws.disconnect(reason: nil)
    }
}

// MARK: - View（对齐 Web ssh_terminal.ftl 完整能力）

struct InstanceSSHView: View {
    let item: InstanceItem
    var onBack: (() -> Void)?
    @EnvironmentObject private var appearance: AppearanceController
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: InstanceSSHViewModel

    init(item: InstanceItem, onBack: (() -> Void)? = nil) {
        self.item = item
        self.onBack = onBack
        _model = StateObject(wrappedValue: InstanceSSHViewModel(item: item))
    }

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(spacing: 0) {
            header
            configBar
            terminalToolbar
            if model.showSearch {
                searchBar
            }
            if let err = model.errorText, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "f85149"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            if model.isTransferring {
                ProgressView(value: max(model.transferProgress, 0.05))
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            TerminalEmulatorView(
                output: $model.output,
                isInteractive: model.isConnected,
                onInput: { model.sendInput($0) },
                fontSize: model.fontSize,
                theme: model.terminalTheme,
                onResize: { cols, rows in model.onTerminalResize(cols: cols, rows: rows) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(AppTheme.pageBg(dark))
        .onAppear {
            FloatingMenuDismiss.all()
            model.start()
        }
        .onDisappear { model.teardown() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if onBack != nil {
                AppButton(title: "返回", systemImage: "chevron.left", kind: .secondary) {
                    model.teardown()
                    onBack?()
                }
            }
            Image(systemName: "terminal")
                .foregroundColor(AppTheme.sidebarActive)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isConnected
                     ? "\(model.username)@\(model.host)"
                     : "SSH — \(item.displayName.isEmpty ? "实例" : item.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isConnected ? Color(hex: "3fb950") : Color(hex: "8b949e"))
                        .frame(width: 7, height: 7)
                    Text(model.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(model.isConnected ? Color(hex: "3fb950") : AppTheme.sidebarText(dark))
                }
            }
            Spacer()
            AppButton(
                title: "保存配置",
                systemImage: "square.and.arrow.down",
                kind: .secondary,
                isLoading: model.isBusy
            ) {
                model.saveConfig()
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

    // MARK: Config

    private var configBar: some View {
        HStack(spacing: 10) {
            labeledField("用户", text: $model.username, width: 100)
            labeledField("地址", text: $model.host, width: 150)
            labeledField("端口", text: $model.port, width: 60)
            HStack(spacing: 4) {
                Text("密码")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
                if model.showPassword {
                    field(text: $model.password, width: 130, placeholder: "密码")
                } else {
                    SecureField("密码", text: $model.password)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .frame(width: 130, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppInputStyle.fill(dark, focused: false)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppInputStyle.border(dark, focused: false), lineWidth: 1))
                }
                iconBtn(model.showPassword ? "eye.slash" : "eye", tip: "显示/隐藏") {
                    model.showPassword.toggle()
                }
                iconBtn("doc.on.doc", tip: "复制密码") { model.copyPassword() }
            }
            Spacer(minLength: 4)
            if model.isConnected {
                AppButton(title: "重连", systemImage: "arrow.clockwise", kind: .secondary) {
                    model.reconnect()
                }
                AppButton(title: "断开", kind: .danger) { model.disconnect() }
            } else {
                AppButton(
                    title: "连接",
                    systemImage: "bolt.fill",
                    kind: .primary,
                    isLoading: model.isConnecting
                ) { model.connect() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.sidebarBg(dark).opacity(0.65))
    }

    // MARK: Terminal toolbar

    private var terminalToolbar: some View {
        // macOS 11 ViewBuilder HStack 最多 10 个子视图，分组打包
        HStack(spacing: 6) {
            Group {
                toolBtn("清屏", "eraser", tip: "Ctrl+L") { model.clearOutput() }
                toolBtn("复制命令", "link", tip: "复制 ssh 命令") { model.copySSHCommand() }
                toolBtn("下载日志", "arrow.down.doc", tip: "导出终端日志") { model.downloadLog() }
            }
            divider
            Group {
                toolBtn("上传", "arrow.up.doc", tip: "SFTP 上传文件") { model.uploadFile() }
                    .disabled(!model.isConnected)
                    .opacity(model.isConnected ? 1 : 0.45)
                toolBtn("下载", "arrow.down.doc.fill", tip: "SFTP 下载文件") { model.downloadFile() }
                    .disabled(!model.isConnected)
                    .opacity(model.isConnected ? 1 : 0.45)
            }
            divider
            Group {
                toolBtn("", "minus", tip: "减小字号") { model.changeFont(-1) }
                Text("\(Int(model.fontSize))px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .frame(width: 36)
                toolBtn("", "plus", tip: "增大字号") { model.changeFont(1) }
            }
            divider
            SelectMenu(
                options: model.themeOptions,
                selection: Binding(
                    get: { model.themeKey },
                    set: { model.setTheme($0 ?? "matrix") }
                ),
                placeholder: "主题",
                width: 130,
                allowClear: false,
                searchable: false
            )
            toolBtn("搜索", "magnifyingglass", tip: "⌘F") {
                model.showSearch.toggle()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBg(dark).opacity(0.4))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.4)),
            alignment: .bottom
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.sidebarText(dark))
            TextField("搜索终端内容…", text: $model.searchQuery, onCommit: {
                model.updateSearch()
            })
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 12))
            .onChange(of: model.searchQuery) { _ in model.updateSearch() }
            if !model.searchHitText.isEmpty {
                Text(model.searchHitText)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            Button(action: { model.showSearch = false; model.searchQuery = ""; model.searchHitText = "" }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarHover(dark).opacity(0.5))
    }

    private var footer: some View {
        HStack {
            Text(model.isConnected
                 ? "\(model.username)@\(model.host):\(model.port)"
                 : "等待连接")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.sidebarText(dark))
            Spacer()
            Text("\(model.termCols) × \(model.termRows)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.sidebarText(dark))
            Text("·")
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.5))
            Text("粘贴 ⌘V · 复制 ⌘C · 清屏后可下载日志")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.sidebarText(dark))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBg(dark))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppTheme.border(dark).opacity(0.55)),
            alignment: .top
        )
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.border(dark).opacity(0.5))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
            field(text: text, width: width, placeholder: label)
        }
    }

    private func field(text: Binding<String>, width: CGFloat, placeholder: String) -> some View {
        TextField(placeholder, text: text, onCommit: {
            if !model.isConnected { model.connect() }
        })
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(width: width, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppInputStyle.fill(dark, focused: false)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppInputStyle.border(dark, focused: false), lineWidth: 1))
    }

    private func iconBtn(_ systemImage: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.sidebarActive)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.sidebarActive.opacity(0.12))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tip)
    }

    private func toolBtn(_ title: String, _ systemImage: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
            .padding(.horizontal, title.isEmpty ? 8 : 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.border(dark).opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tip)
    }
}
