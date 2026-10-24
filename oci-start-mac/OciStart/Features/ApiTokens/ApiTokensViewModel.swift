import Foundation
import Combine
import AppKit

@MainActor
final class ApiTokensViewModel: ObservableObject {
    @Published var form = ApiTokenForm()
    @Published private(set) var status: ApiTokenStatus?
    @Published private(set) var editing = false
    @Published private(set) var isLoading = false
    @Published private(set) var savingKey: String?
    @Published private(set) var errorText: String?
    @Published private(set) var notice: String?
    @Published private(set) var displayToken = ""
    @Published private(set) var materialLoading = false
    @Published private(set) var requiresReview = false
    @Published private(set) var reviewReady = false
    @Published private(set) var expired: Bool?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var appActive = NSApp.isActive
    @Published var reviewChecked = false
    private var baseline = ApiTokenForm()
    private var editorRevision = ""
    private var sequence = 0
    private var materialSequence = 0
    private var materialRevision = ""
    private var expiresMonotonic: TimeInterval?
    private var expiresWall: Date?
    private var hiddenAt: Date?
    private var observers = Set<AnyCancellable>()
    private var active = false
    private let owner = UUID()
    private let session: AppSession
    private var service: ApiTokensService { ApiTokensService(baseURL: session.serverURL) }

    init(session: AppSession = .shared) { self.session = session }
    var dirty: Bool { editing && form != baseline }
    var busy: Bool { savingKey != nil }
    var staleEditor: Bool { editing && editorRevision != status?.revision }
    var canMutate: Bool { status != nil && !isLoading && !busy && !materialLoading && !requiresReview && errorText == nil && appActive }
    var canReveal: Bool { status?.hasToken == true && status?.enabled == true && expired == false && status?.expiresAtEpochMs != nil && !busy && !isLoading && !materialLoading && errorText == nil && appActive }
    var statusLabel: String {
        guard let status = status else { return "尚未加载" }
        if !status.hasToken { return "未生成" }
        if !status.enabled { return "已停用" }
        if expired == true { return "已过期" }
        if expired == nil { return "有效期未确认" }
        return "有效"
    }
    var expireOptions: [SelectOption] {
        Array(Set([7, 30, 90, 180, 365, form.expirationDays])).sorted().filter { (1...365).contains($0) }
            .map { SelectOption(id: "\($0)", title: LanguageManager.shared.text("\($0) 天", "\($0) days")) }
    }

    func start() {
        guard !active else { return }
        active = true
        appActive = NSApp.isActive
        NavigationState.shared.setLeaveGuard(owner: owner) { [weak self] in self?.canLeave() ?? true }
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.appActive = false; model.hideMaterial() }
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.appActive = true; model.checkExpiry() }
        }.store(in: &observers)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.checkExpiry() }
        }.store(in: &observers)
        Task { await reload() }
    }

    func stop() {
        active = false; sequence += 1
        hideMaterial(); observers.removeAll()
        NavigationState.shared.removeLeaveGuard(owner: owner)
    }

    func canLeave() -> Bool {
        if busy || requiresReview {
            AppAlert.info(title: "操作尚未完成", message: busy ? "请等待 Token 操作完成。" : "请刷新并核对服务器结果，再确认完成核对。")
            return false
        }
        return !dirty || AppAlert.confirm(title: "放弃修改", message: "尚未提交的 Token 配置将被丢弃。", confirmTitle: "放弃修改")
    }

    func reload() async {
        guard !busy else { return }
        hideMaterial()
        await load()
    }

    private func load() async {
        sequence += 1
        let current = sequence, server = session.serverURL
        let began = ProcessInfo.processInfo.systemUptime
        isLoading = true; errorText = nil; reviewReady = false; reviewChecked = false
        do {
            let result = try await service.fetchConfigs()
            guard active, current == sequence, server == session.serverURL else { return }
            accept(result, started: began)
            lastUpdated = Date()
            reviewReady = requiresReview
        } catch {
            if active && current == sequence { errorText = error.localizedDescription }
        }
        if current == sequence { isLoading = false }
    }

    private func accept(_ value: ApiTokenStatus, started: TimeInterval) {
        if !materialRevision.isEmpty && materialRevision != value.revision { hideMaterial() }
        status = value; expired = value.isExpired
        expiresMonotonic = nil; expiresWall = nil
        if let end = value.expiresAtEpochMs {
            let lifetime = Double(end - value.serverTime) / 1000 - max(0, ProcessInfo.processInfo.systemUptime - started)
            expiresMonotonic = ProcessInfo.processInfo.systemUptime + lifetime
            expiresWall = Date().addingTimeInterval(lifetime)
        }
        checkExpiry()
    }

    private func checkExpiry() {
        if let mono = expiresMonotonic, let wall = expiresWall,
           ProcessInfo.processInfo.systemUptime >= mono || Date() >= wall { expired = true }
        if expired == true && (!displayToken.isEmpty || materialLoading) { hideMaterial() }
        if let deadline = hiddenAt, Date() >= deadline { hideMaterial() }
    }

    func hideMaterial() {
        materialSequence += 1; displayToken = ""; materialRevision = ""; hiddenAt = nil; materialLoading = false
    }

    func reveal() {
        guard canReveal, let revision = status?.revision else { return }
        hideMaterial()
        let current = materialSequence, began = ProcessInfo.processInfo.systemUptime
        materialLoading = true
        Task {
            do {
                let result = try await service.material(revision: revision)
                if active && current == materialSequence && status?.revision == revision && NSApp.isActive {
                    accept(result.metadata, started: began)
                    if expired == false && result.metadata.enabled {
                        displayToken = result.tokenValue; materialRevision = revision
                        hiddenAt = Date().addingTimeInterval(10)
                    }
                }
            } catch { if active && current == materialSequence { errorText = error.localizedDescription } }
            if current == materialSequence { materialLoading = false }
        }
    }

    func openEditor() {
        guard canMutate, let state = status else { return }
        hideMaterial(); notice = nil
        form = state.form; baseline = form; editorRevision = state.revision; editing = true
    }

    func back() {
        guard canLeave() else { return }
        if editing { editing = false; form = ApiTokenForm(); baseline = form; editorRevision = "" }
        else { NavigationState.shared.select(.dashboard) }
    }

    func useLatest() {
        guard !isLoading, !busy, !requiresReview, errorText == nil, let revision = status?.revision else { return }
        editorRevision = revision
    }

    func generate() {
        guard canMutate, form.valid, !staleEditor else { return }
        let snapshot = form, revision = editorRevision
        let message = "名称：\(snapshot.tokenName.trimmingCharacters(in: .whitespacesAndNewlines))\n有效期：\(snapshot.expirationDays) 天\n\n" +
            (status?.hasToken == true ? "生成后旧 Token 将立即失效。" : "确认生成 API 访问令牌？")
        guard AppAlert.confirm(title: "生成 Token", message: message, confirmTitle: "确认生成") else { return }
        Task { await mutate(kind: "generate", form: snapshot, revision: revision) }
    }

    func revoke() {
        guard canMutate, let state = status, state.hasToken || state.enabled else { return }
        guard AppAlert.confirm(title: "撤销 Token", message: "名称：\(state.tokenName)\n撤销后，使用此 Token 的 API 请求将失败。", confirmTitle: "确认撤销") else { return }
        Task { await mutate(kind: "revoke", form: nil, revision: state.revision) }
    }

    private func mutate(kind: String, form: ApiTokenForm?, revision: String) async {
        guard canMutate else { return }
        hideMaterial(); savingKey = kind; errorText = nil; notice = nil
        let expectedMaterialSequence = materialSequence
        let server = session.serverURL, began = ProcessInfo.processInfo.systemUptime
        do {
            let receipt: ApiTokenStatus
            var token = ""
            if let form = form {
                let generated = try await service.generate(form, revision: revision)
                receipt = generated.metadata; token = generated.tokenValue
            } else { receipt = try await service.revoke(revision: revision) }
            if active && server == session.serverURL {
                accept(receipt, started: began)
                if !token.isEmpty && NSApp.isActive && expired != true && materialSequence == expectedMaterialSequence {
                    displayToken = token; materialRevision = receipt.revision; hiddenAt = Date().addingTimeInterval(10)
                }
                editing = false; self.form = ApiTokenForm(); baseline = self.form
                notice = kind == "generate" ? "Token 已生成，请妥善保存。" : "Token 已撤销。"
                await load()
                if let actual = status, actual.revision != receipt.revision, errorText == nil {
                    notice = "操作已有成功回执，但服务器配置随后发生了变化，当前显示最新状态。"
                }
            }
        } catch {
            if active {
                let failure = (error as? ApiTokenFailure) ?? ApiTokenFailure(key: "requestFailed", writeAttempted: true)
                errorText = failure.localizedDescription
                if failure.writeAttempted {
                    requiresReview = true; editing = false
                    notice = "未收到明确回执，请核对服务器状态。不要重复提交相同操作。"
                    await load()
                } else if failure.key == "conflict" || failure.key == "notFound" {
                    let reason = errorText
                    await load()
                    notice = reason
                }
            }
        }
        savingKey = nil
    }

    func acknowledgeReview() {
        guard requiresReview, reviewReady, reviewChecked, !busy else { return }
        requiresReview = false; reviewReady = false; reviewChecked = false; notice = nil
    }

    func copyToken() {
        checkExpiry()
        guard !displayToken.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayToken, forType: .string)
    }

    func copyAuthHeader() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Authorization: Bearer <TOKEN>", forType: .string)
    }

    func openURL(_ path: String) {
        guard let url = try? APIClient.shared.makeURL(session.serverURL, path: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
