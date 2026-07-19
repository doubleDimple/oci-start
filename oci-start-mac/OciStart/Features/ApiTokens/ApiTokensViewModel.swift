import Foundation
import Combine
import AppKit

@MainActor
final class ApiTokensViewModel: ObservableObject {
    @Published var form = ApiTokenForm()
    @Published var status = ApiTokenStatus()
    @Published var lastGenerated: ApiTokenGenerateResult?
    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: ApiTokensService { ApiTokensService(baseURL: session.serverURL) }

    var expireOptions: [SelectOption] {
        [7, 30, 90, 180, 365].map { SelectOption(id: "\($0)", title: "\($0) 天") }
    }

    var displayToken: String {
        if let g = lastGenerated, !g.tokenValue.isEmpty { return g.tokenValue }
        return status.tokenValue
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
            let result = try await service.fetchConfigs()
            form = result.form
            status = result.status
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func generate() {
        Task { await performGenerate() }
    }

    private func performGenerate() async {
        let name = form.tokenName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.error("请填写 Token 名称")
            return
        }
        let ok = AppAlert.confirm(
            title: "生成新 Token",
            message: "生成后旧 Token 将立即失效，确认继续？",
            confirmTitle: "生成"
        )
        guard ok else { return }

        var payload = form
        payload.tokenName = name
        savingKey = "generate"
        defer { savingKey = nil }
        do {
            let result = try await LoadingHUD.shared.during {
                try await service.generate(payload)
            }
            lastGenerated = result
            await reload()
            status.tokenValue = result.tokenValue
            status.hasToken = true
            status.enabled = true
            AppAlert.info(
                title: "Token 已生成",
                message: "请妥善保存：\n\n\(result.tokenValue)\n\n有效期约 \(result.daysUntilExpiration) 天\(result.expiresAt.isEmpty ? "" : "（\(result.expiresAt)）")"
            )
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func revoke() {
        Task { await performRevoke() }
    }

    private func performRevoke() async {
        guard status.enabled || status.hasToken else {
            ToastCenter.shared.error("当前没有可撤销的 Token")
            return
        }
        let ok = AppAlert.confirm(
            title: "撤销 Token",
            message: "撤销后所有使用该 Token 的 API 调用将失败，确认继续？",
            confirmTitle: "撤销"
        )
        guard ok else { return }
        savingKey = "revoke"
        defer { savingKey = nil }
        do {
            try await LoadingHUD.shared.during {
                try await service.revoke()
            }
            lastGenerated = nil
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func copyToken() {
        let token = displayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            ToastCenter.shared.error("暂无 Token 可复制")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    func copyAuthHeader() {
        let token = displayToken.isEmpty ? "{your_token}" : displayToken
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Authorization: Bearer \(token)", forType: .string)
    }

    func openURL(_ path: String) {
        let base = session.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { return }
        NSWorkspace.shared.open(url)
    }
}
