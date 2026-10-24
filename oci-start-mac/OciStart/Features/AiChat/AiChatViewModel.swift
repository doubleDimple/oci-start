import Foundation
import Combine
import AppKit

struct AiChatTimeouts {
    var initialization: TimeInterval = 30
    var reply: TimeInterval = 300
    var heartbeat: TimeInterval = 30
    var silence: TimeInterval = 90
}

@MainActor
final class AiChatViewModel: ObservableObject {
    @Published private(set) var tenants: [AiChatTenantOption] = []
    @Published var selectedTenantId: Int64?
    @Published private(set) var models: [AiChatModelOption] = []
    @Published var selectedModelId: String = ""
    @Published var messages: [AiChatMessage] = []
    @Published var input: String = ""
    @Published var useHistory = true
    @Published private(set) var statusText = "请选择租户"
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoadingTenants = false
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isSending = false
    @Published private(set) var errorText: String?
    @Published var tenantSearch = ""

    private let session: AppSession
    private let serviceOverride: AiChatServing?
    private var service: AiChatServing { serviceOverride ?? AiChatService(baseURL: session.serverURL) }
    private let ws: NativeWSConnection
    private let timeouts: AiChatTimeouts
    private var active = false
    private var currentTenantId: Int64 = 0
    private var tenantGeneration = 0
    private var modelGeneration = 0
    private var connectionGeneration = 0
    private var replyGeneration = 0
    private var modelTask: Task<Void, Never>?
    private var initializationDeadline: DispatchWorkItem?
    private var replyDeadline: DispatchWorkItem?
    private var heartbeat: DispatchSourceTimer?
    private var lastPacketAt: TimeInterval = 0
    private var activeReplyId: UUID?

    var filteredTenants: [AiChatTenantOption] {
        let q = tenantSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tenants }
        return tenants.filter {
            $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q)
        }
    }

    var selectedTenant: AiChatTenantOption? { tenants.first { $0.id == selectedTenantId } }
    var canCancel: Bool { isLoadingTenants || isLoadingModels || isConnecting || isSending }

    init(session: AppSession = .shared, service: AiChatServing? = nil,
         ws: NativeWSConnection = NativeWSClient(), timeouts: AiChatTimeouts = AiChatTimeouts()) {
        self.session = session
        self.serviceOverride = service
        self.ws = ws
        self.timeouts = timeouts
        seedWelcome()
    }

    func start() {
        guard !active else { return }
        active = true
        refreshTenants()
    }

    func refreshTenants() {
        let generation = tenantGeneration
        Task { [weak self] in
            guard let self = self, self.active, self.tenantGeneration == generation else { return }
            await self.loadTenants()
        }
    }

    func teardown() {
        active = false
        invalidateLoads()
        disconnect()
    }

    /// Navigation can publish before onAppear. Remember the exact tenant and
    /// let the single tenant load apply it, instead of starting a second load.
    func consumePendingTenant() {
        guard let id = NavigationState.shared.takePendingAiChatTenantId(), id > 0 else { return }
        selectedTenantId = id
        // In an existing conversation, switch immediately even while a list
        // refresh is pending; otherwise the selection and live socket diverge.
        if active, currentTenantId > 0 || !tenants.isEmpty { selectTenant(id) }
    }

    func loadTenants() async {
        guard active, !isLoadingTenants else { return }
        tenantGeneration += 1
        let generation = tenantGeneration
        isLoadingTenants = true
        errorText = nil
        defer { if generation == tenantGeneration { isLoadingTenants = false } }
        do {
            let loaded = try await service.listTenants()
            guard active, generation == tenantGeneration else { return }
            tenants = loaded
            let pending = NavigationState.shared.takePendingAiChatTenantId()
            // A selected child tenant may be outside the first list page.
            if let id = pending ?? selectedTenantId, id > 0 {
                selectTenant(id)
            } else if let first = tenants.first {
                selectTenant(first.id)
            } else {
                statusText = "暂无可用租户"
            }
        } catch {
            guard active, generation == tenantGeneration else { return }
            showError(error.localizedDescription)
        }
    }

    func selectTenant(_ id: Int64, force: Bool = false) {
        guard active, id > 0 else { return }
        if !force, currentTenantId == id, isConnected || isConnecting || isLoadingModels { return }
        modelTask?.cancel()
        modelGeneration += 1
        disconnect()
        selectedTenantId = id
        currentTenantId = id
        models = []
        selectedModelId = ""
        errorText = nil
        clearChat(keepWelcome: true)
        isLoadingModels = true
        statusText = "加载模型…"
        let generation = modelGeneration
        modelTask = Task { await loadModels(tenantId: id, generation: generation) }
    }

    private func loadModels(tenantId: Int64, generation: Int) async {
        defer { if generation == modelGeneration { isLoadingModels = false } }
        do {
            let loaded = try await service.models(tenantId: tenantId)
            guard active, generation == modelGeneration, currentTenantId == tenantId, !Task.isCancelled else { return }
            models = loaded
            selectedModelId = models.first?.id ?? ""
            isLoadingModels = false
            if models.isEmpty { showError("该租户暂无可用模型") }
            else { connect() }
        } catch {
            guard active, generation == modelGeneration, !Task.isCancelled else { return }
            showError(error.localizedDescription)
        }
    }

    func onModelChanged() {
        guard active, !isLoadingModels, !isSending, selectedTenantId != nil else { return }
        connect()
    }

    func cancel() {
        invalidateLoads()
        disconnect()
        errorText = nil
        statusText = "已取消"
    }

    func reconnect() {
        guard active, !canCancel else { return }
        guard let id = selectedTenantId, id > 0 else {
            refreshTenants()
            return
        }
        currentTenantId = id
        if models.contains(where: { $0.id == selectedModelId }) { connect() }
        else { selectTenant(id, force: true) }
    }

    private func invalidateLoads() {
        tenantGeneration += 1
        modelGeneration += 1
        modelTask?.cancel()
        modelTask = nil
        isLoadingTenants = false
        isLoadingModels = false
    }

    // MARK: - Chat

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Return/keyboard shortcuts must obey the same gate as the send button.
        guard active, !text.isEmpty, !isSending, !isLoadingModels, isConnected,
              currentTenantId > 0, selectedTenantId == currentTenantId,
              models.contains(where: { $0.id == selectedModelId }) else { return }
        messages.append(AiChatMessage(role: .user, text: text))
        input = ""
        errorText = nil
        isSending = true
        activeReplyId = nil
        statusText = "AI 思考中…"
        armReplyDeadline()
        ws.sendJSON([
            "type": "chat", "message": text, "modelId": selectedModelId,
            "tenantId": "\(currentTenantId)", "useHistory": useHistory
        ])
    }

    func clearChat(keepWelcome: Bool = false) {
        guard !isSending else { return }
        messages.removeAll()
        if keepWelcome { seedWelcome() }
    }

    func copyLastAssistant() {
        guard let last = messages.last(where: { $0.role == .assistant }) else {
            ToastCenter.shared.error("暂无回复可复制")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
        ToastCenter.shared.success("已复制 AI 回复")
    }

    // MARK: - WS

    private func connect() {
        disconnect()
        guard active, currentTenantId > 0, models.contains(where: { $0.id == selectedModelId }) else { return }
        let generation = connectionGeneration
        let tenantId = currentTenantId
        let modelId = selectedModelId
        isConnecting = true
        errorText = nil
        statusText = "连接中…"
        ws.onState = { [weak self] state in
            guard let self = self, self.active, self.connectionGeneration == generation else { return }
            switch state {
            case .open:
                guard self.isConnecting else { return }
                self.statusText = "准备 AI 会话…"
                self.startHeartbeat(generation: generation)
                self.ws.sendJSON(["type": "init", "tenant": ["tenantId": "\(tenantId)", "modelId": modelId]])
            case .closed(let reason):
                self.fail(reason.map { "连接已断开：\($0)" } ?? "连接已断开，请重新连接")
            default: break
            }
        }
        ws.onText = { [weak self] text in
            guard let self = self, self.active, self.connectionGeneration == generation else { return }
            self.lastPacketAt = ProcessInfo.processInfo.systemUptime
            self.handleWS(text)
        }
        ws.onBinary = { [weak self] data in
            guard let self = self, self.active, self.connectionGeneration == generation else { return }
            guard let text = String(data: data, encoding: .utf8) else { self.fail("AI 响应格式无效，请重新连接"); return }
            self.lastPacketAt = ProcessInfo.processInfo.systemUptime
            self.handleWS(text)
        }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.connectionGeneration == generation, self.isConnecting else { return }
            self.fail("AI 会话准备超时，请检查服务连接后重试")
        }
        initializationDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + timeouts.initialization, execute: deadline)
        do { ws.connect(url: try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/aiChat")) }
        catch { fail(error.localizedDescription) }
    }

    private func disconnect() {
        connectionGeneration += 1
        initializationDeadline?.cancel()
        initializationDeadline = nil
        heartbeat?.cancel()
        heartbeat = nil
        finishReply()
        ws.onState = nil
        ws.onText = nil
        ws.onBinary = nil
        ws.disconnect(reason: nil)
        isConnected = false
        isConnecting = false
    }

    private func startHeartbeat(generation: Int) {
        heartbeat?.cancel()
        lastPacketAt = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + timeouts.heartbeat, repeating: timeouts.heartbeat)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.active, self.connectionGeneration == generation else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastPacketAt > self.timeouts.silence {
                self.fail("连接长时间没有响应，请重新连接")
            } else { self.ws.sendJSON(["type": "ping"]) }
        }
        heartbeat = timer
        timer.resume()
    }

    private func armReplyDeadline() {
        replyDeadline?.cancel()
        replyGeneration += 1
        let generation = connectionGeneration
        let reply = replyGeneration
        let deadline = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.connectionGeneration == generation,
                  self.replyGeneration == reply, self.isSending else { return }
            self.fail("AI 回复等待超时，请检查模型服务后重新连接")
        }
        replyDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + timeouts.reply, execute: deadline)
    }

    private func finishReply() {
        replyGeneration += 1
        replyDeadline?.cancel()
        replyDeadline = nil
        if let id = activeReplyId, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
        }
        activeReplyId = nil
        isSending = false
    }

    private func showError(_ message: String) {
        errorText = message
        statusText = message
        ToastCenter.shared.error(message)
    }

    private func fail(_ message: String) {
        disconnect()
        showError(message)
    }

    private func handleWS(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            fail("AI 响应格式无效，请重新连接")
            return
        }
        switch type {
        case "init":
            guard isConnecting else { return }
            guard obj["status"] as? String == "success" else {
                fail((obj["message"] as? String) ?? "AI 会话初始化失败")
                return
            }
            initializationDeadline?.cancel()
            initializationDeadline = nil
            isConnecting = false
            isConnected = true
            statusText = "已连接"
        case "typing":
            if isSending { armReplyDeadline() }
        case "chat":
            guard isSending, obj["role"] as? String == "assistant" else { return }
            guard let message = obj["message"] as? String else { fail("AI 响应格式无效，请重新连接"); return }
            armReplyDeadline()
            let isChunk = obj["isChunk"] as? Bool == true
            if let id = activeReplyId, let index = messages.firstIndex(where: { $0.id == id }) {
                messages[index].text = isChunk ? messages[index].text + message : message
            } else {
                let reply = AiChatMessage(role: .assistant, text: message, isStreaming: true)
                activeReplyId = reply.id
                messages.append(reply)
            }
            statusText = "AI 正在回复…"
        case "chat_end":
            guard isSending else { return }
            guard obj["status"] as? String == "success" else {
                fail((obj["message"] as? String) ?? "AI 回复失败")
                return
            }
            guard let id = activeReplyId, let reply = messages.first(where: { $0.id == id }),
                  !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("模型未返回回复内容，请重试或切换模型")
                return
            }
            finishReply()
            statusText = "已连接"
        case "error":
            fail((obj["message"] as? String) ?? "AI 服务返回错误，请重新连接")
        case "heartbeat", "pong", "system", "history":
            // Keep-alives prove connection health, not progress on a reply.
            break
        default: break
        }
    }

    private func seedWelcome() {
        messages = [AiChatMessage(role: .assistant, text: "你好！我是 OCI AI 助手。选择左侧租户与模型后，即可开始对话。")]
    }
}
