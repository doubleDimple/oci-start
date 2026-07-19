import Foundation
import Combine

@MainActor
final class NotifyViewModel: ObservableObject {
    @Published var task = NotifyTaskForm()
    @Published var telegram = NotifyTelegramForm()
    @Published var proxy = NotifyProxyForm()
    @Published var bark = NotifyBarkForm()
    @Published var dingTalk = NotifyWebhookForm()
    @Published var feishu = NotifyWebhookForm()

    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: NotifyService { NotifyService(baseURL: session.serverURL) }

    var hourOptions: [SelectOption] {
        (0...23).map { SelectOption(id: "\($0)", title: String(format: "%02d:00", $0)) }
    }

    var proxyTypeOptions: [SelectOption] {
        ["HTTP", "HTTPS", "SOCKS5"].map { SelectOption(id: $0, title: $0) }
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let cfg = try await service.fetchConfigs()
            task = cfg.task
            telegram = cfg.telegram
            proxy = cfg.proxy
            bark = cfg.bark
            dingTalk = cfg.dingTalk
            feishu = cfg.feishu
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func saveTask() { Task { await perform("task") { try await service.updateTask(task) } } }
    func saveTelegram() { Task { await perform("telegram") { try await service.updateTelegram(telegram) } } }
    func testTelegram() { Task { await perform("telegramTest") { try await service.testTelegram() } } }
    func saveBark() { Task { await perform("bark") { try await service.updateBark(bark) } } }
    func testBark() { Task { await perform("barkTest") { try await service.testBark() } } }
    func saveDingTalk() { Task { await perform("dingTalk") { try await service.updateDingTalk(dingTalk) } } }
    func testDingTalk() { Task { await perform("dingTalkTest") { try await service.testDingTalk() } } }
    func saveFeishu() { Task { await perform("feishu") { try await service.updateFeishu(feishu) } } }
    func testFeishu() { Task { await perform("feishuTest") { try await service.testFeishu() } } }

    func saveProxy() {
        Task {
            guard (1...65535).contains(proxy.port) else {
                ToastCenter.shared.error("端口范围应为 1–65535")
                return
            }
            await perform("proxy") { try await service.updateProxy(proxy) }
        }
    }

    func testProxy() {
        Task {
            await perform("proxyTest") {
                _ = try await service.testProxy(proxy)
            }
        }
    }

    private func perform(_ key: String, _ work: () async throws -> Void) async {
        savingKey = key
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await work()
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
