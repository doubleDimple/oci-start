import Foundation
import Combine
import AppKit

/// ViewModel for Web `/system/domainSettings`.
@MainActor
final class KeyConfigViewModel: ObservableObject {
    @Published var cloudflare = CloudflareKeyConfig()
    @Published var edgeOne = EdgeOneKeyConfig()

    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: KeyConfigService { KeyConfigService(baseURL: session.serverURL) }

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
            cloudflare = cfg.cloudflare
            edgeOne = cfg.edgeOne
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Cloudflare

    func saveCloudflare() {
        Task { await performSaveCloudflare() }
    }

    private func performSaveCloudflare() async {
        var cfg = cloudflare
        cfg.apiToken = cfg.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.email = cfg.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if cfg.enabled {
            if cfg.apiToken.isEmpty || cfg.email.isEmpty {
                ToastCenter.shared.error("启用时请填写 API Key 与账户邮箱")
                return
            }
        }
        let ok = AppAlert.confirm(
            title: "保存 Cloudflare 配置",
            message: "确认保存当前密钥配置？",
            confirmTitle: "保存"
        )
        guard ok else { return }
        cloudflare = cfg
        savingKey = "cf-save"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateCloudflare(cfg)
            }
            ToastCenter.shared.success("Cloudflare 配置已保存")
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func testCloudflare() {
        Task { await performTestCloudflare() }
    }

    private func performTestCloudflare() async {
        let token = cloudflare.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = cloudflare.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty || email.isEmpty {
            ToastCenter.shared.error("请填写 API Key 与账户邮箱后再测试")
            return
        }
        savingKey = "cf-test"
        defer { savingKey = nil }
        do {
            var cfg = cloudflare
            cfg.apiToken = token
            cfg.email = email
            let msg = try await LoadingHUD.shared.during {
                try await service.testCloudflare(cfg)
            }
            AppAlert.info(title: "连接测试", message: msg)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - EdgeOne

    func saveEdgeOne() {
        Task { await performSaveEdgeOne() }
    }

    private func performSaveEdgeOne() async {
        var cfg = edgeOne
        cfg.secretId = cfg.secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.secretKey = cfg.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cfg.enabled {
            if cfg.secretId.isEmpty || cfg.secretKey.isEmpty {
                ToastCenter.shared.error("启用时请填写 SecretId 与 SecretKey")
                return
            }
        }
        let ok = AppAlert.confirm(
            title: "保存 EdgeOne 配置",
            message: "确认保存当前密钥配置？",
            confirmTitle: "保存"
        )
        guard ok else { return }
        edgeOne = cfg
        savingKey = "eo-save"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.updateEdgeOne(cfg)
            }
            ToastCenter.shared.success("EdgeOne 配置已保存")
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func testEdgeOne() {
        Task { await performTestEdgeOne() }
    }

    private func performTestEdgeOne() async {
        let sid = edgeOne.secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        let skey = edgeOne.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if sid.isEmpty || skey.isEmpty {
            ToastCenter.shared.error("请填写 SecretId 与 SecretKey 后再测试")
            return
        }
        savingKey = "eo-test"
        defer { savingKey = nil }
        do {
            var cfg = edgeOne
            cfg.secretId = sid
            cfg.secretKey = skey
            let msg = try await LoadingHUD.shared.during {
                try await service.testEdgeOne(cfg)
            }
            AppAlert.info(title: "连接测试", message: msg)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func copy(_ text: String, label: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            ToastCenter.shared.error("暂无 \(label) 可复制")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
        ToastCenter.shared.success("已复制 \(label)")
    }
}
