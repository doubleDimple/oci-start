import Foundation
import Combine
import AppKit

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
    @Published private(set) var isLoadingTenants = false
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isSending = false
    @Published private(set) var errorText: String?
    @Published var tenantSearch = ""

    private let session: AppSession
    private var service: AiChatService { AiChatService(baseURL: session.serverURL) }
    private let ws = NativeWSClient()
    private var currentTenantId: Int64 = 0

    var filteredTenants: [AiChatTenantOption] {
        let q = tenantSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tenants }
        return tenants.filter {
            $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q)
        }
    }

    var selectedTenant: AiChatTenantOption? {
        tenants.first { $0.id == selectedTenantId }
    }

    init(session: AppSession = .shared) {
        self.session = session
        wireWS()
        seedWelcome()
    }

    func start() {
        Task { await loadTenants() }
    }

    func teardown() {
        disconnect()
    }

    /// 消费导航里带过来的租户（租户列表点 AI 后跳转）。
    func consumePendingTenant() {
        guard let id = NavigationState.shared.takePendingAiChatTenantId(), id > 0 else { return }
        if tenants.contains(where: { $0.id == id }) {
            selectTenant(id, force: true)
        } else {
            // 列表尚未加载完：先记下，loadTenants 结束后应用
            selectedTenantId = id
            currentTenantId = id
            statusText = "加载租户…"
            Task {
                await loadTenants()
            }
        }
    }

    func loadTenants() async {
        isLoadingTenants = true
        errorText = nil
        defer { isLoadingTenants = false }
        do {
            tenants = try await service.listTenants()
            // 优先：导航预选 → 已选 → 列表第一项
            if let pending = NavigationState.shared.takePendingAiChatTenantId(), pending > 0 {
                selectTenant(pending, force: true)
            } else if let cur = selectedTenantId, tenants.contains(where: { $0.id == cur }) {
                selectTenant(cur, force: selectedModelId.isEmpty)
            } else if let first = tenants.first {
                selectTenant(first.id, force: true)
            }
        } catch {
            errorText = error.localizedDescription
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func selectTenant(_ id: Int64, force: Bool = false) {
        if !force, selectedTenantId == id, isConnected || isLoadingModels { return }
        selectedTenantId = id
        currentTenantId = id
        models = []
        selectedModelId = ""
        clearChat(keepWelcome: true)
        disconnect()
        statusText = "加载模型…"
        Task { await loadModels(tenantId: id) }
    }

    func loadModels(tenantId: Int64) async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            models = try await service.models(tenantId: tenantId)
            selectedModelId = models.first?.id ?? ""
            if models.isEmpty {
                statusText = "该租户暂无可用模型"
            } else {
                connect()
            }
        } catch {
            statusText = error.localizedDescription
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func onModelChanged() {
        guard selectedTenantId != nil else { return }
        connect()
    }

    // MARK: - Chat

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isConnected else {
            ToastCenter.shared.error("WebSocket 未连接")
            return
        }
        guard !selectedModelId.isEmpty else {
            ToastCenter.shared.error("请选择模型")
            return
        }
        guard currentTenantId > 0 else {
            ToastCenter.shared.error("请选择租户")
            return
        }

        messages.append(AiChatMessage(role: .user, text: text))
        input = ""
        isSending = true
        statusText = "AI 思考中…"

        ws.sendJSON([
            "type": "chat",
            "message": text,
            "modelId": selectedModelId,
            "tenantId": "\(currentTenantId)",
            "useHistory": useHistory
        ])
    }

    func clearChat(keepWelcome: Bool = false) {
        messages.removeAll()
        if keepWelcome {
            seedWelcome()
        }
        isSending = false
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

    private func wireWS() {
        ws.onState = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .connecting:
                self.statusText = "连接中…"
            case .closed(let reason):
                self.isConnected = false
                self.isSending = false
                self.statusText = reason.map { "已断开：\($0)" } ?? "已断开"
            default:
                break
            }
        }
        ws.onText = { [weak self] text in
            self?.handleWS(text)
        }
    }

    private func connect() {
        disconnect()
        guard currentTenantId > 0 else { return }
        do {
            let url = try NativeWSURL.make(baseHTTP: session.serverURL, path: "/ws/aiChat")
            ws.connect(url: url)
            statusText = "连接中…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self else { return }
                self.ws.sendJSON([
                    "type": "init",
                    "tenant": [
                        "tenantId": "\(self.currentTenantId)",
                        "modelId": self.selectedModelId
                    ]
                ])
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func disconnect() {
        ws.disconnect(reason: nil)
        isConnected = false
    }

    private func handleWS(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let type = obj["type"] as? String ?? ""
        switch type {
        case "init":
            if let status = obj["status"] as? String, status != "success" {
                statusText = (obj["message"] as? String) ?? "初始化失败"
                isConnected = false
            } else {
                isConnected = true
                statusText = "已连接"
            }
        case "chat":
            let role = obj["role"] as? String ?? ""
            let msg = obj["message"] as? String ?? ""
            guard role == "assistant", !msg.isEmpty else { return }
            let isChunk = (obj["isChunk"] as? Bool) == true
            if isChunk {
                if let last = messages.last, last.role == .assistant, last.isStreaming {
                    var updated = last
                    updated.text += msg
                    messages[messages.count - 1] = updated
                } else {
                    messages.append(AiChatMessage(role: .assistant, text: msg, isStreaming: true))
                }
            } else {
                // 完整消息
                if let last = messages.last, last.role == .assistant, last.isStreaming {
                    var updated = last
                    updated.text = msg
                    updated.isStreaming = false
                    messages[messages.count - 1] = updated
                } else {
                    messages.append(AiChatMessage(role: .assistant, text: msg, isStreaming: false))
                }
            }
        case "chat_end":
            if let last = messages.last, last.role == .assistant, last.isStreaming {
                var updated = last
                updated.isStreaming = false
                messages[messages.count - 1] = updated
            }
            isSending = false
            statusText = isConnected ? "已连接" : statusText
        case "error":
            isSending = false
            let m = (obj["message"] as? String) ?? "AI 错误"
            statusText = m
            ToastCenter.shared.error(m)
            messages.append(AiChatMessage(role: .system, text: m))
        default:
            break
        }
    }

    private func seedWelcome() {
        messages = [
            AiChatMessage(
                role: .assistant,
                text: "你好！我是 OCI AI 助手。选择左侧租户与模型后，即可开始对话。"
            )
        ]
    }
}
