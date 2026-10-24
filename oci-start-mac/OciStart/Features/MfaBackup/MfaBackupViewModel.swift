import Foundation
import Combine
import AppKit

@MainActor
final class MfaBackupViewModel: ObservableObject {
    @Published private(set) var items: [MfaKeyItem] = []
    @Published var searchText = "" { didSet { pageState.goFirst(); pageState.apply(totalElements: Int64(filtered.count)); clearCodes() } }
    @Published var pageState = PageState(page: 0, size: 15)
    @Published private(set) var adding = false
    @Published var mode = "manual" { didSet { candidates = []; partialBatch = false } }
    @Published var keyName = ""
    @Published var issuer = ""
    @Published var secretKey = ""
    @Published var qrURI = ""
    @Published private(set) var imageURL: URL?
    @Published private(set) var imageName = ""
    private var imageData: Data?
    @Published var candidates: [MfaCandidate] = []
    @Published private(set) var partialBatch = false
    @Published var material: MfaMaterial?
    @Published private(set) var codes: [String: String] = [:]
    @Published private(set) var countdown = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var errorText: String?
    @Published private(set) var resultText: String?
    @Published private(set) var requiresReview = false
    @Published private(set) var reviewReady = false
    @Published private(set) var loaded = false
    @Published private(set) var loadFailed = false

    private let session: AppSession
    private var service: MfaBackupService { MfaBackupService(baseURL: session.serverURL) }
    private var timer: Timer?
    private var active = false
    private var generation = 0
    private var codesGeneration = 0
    private var refreshingCodes = false
    private var nextCodesAt: TimeInterval = 0
    private var expiresAt: TimeInterval = 0
    var busy: Bool { isLoading || isSaving || isPreviewing }
    var canMutate: Bool { loaded && !loadFailed && !busy && !requiresReview }
    var filtered: [MfaKeyItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { q.isEmpty || $0.keyName.localizedCaseInsensitiveContains(q) || $0.issuer.localizedCaseInsensitiveContains(q) }
    }
    var pageItems: [MfaKeyItem] { Array(filtered.dropFirst(pageState.page * pageState.size).prefix(pageState.size)) }
    var hasDraft: Bool { adding && (!keyName.isEmpty || !issuer.isEmpty || !secretKey.isEmpty || !qrURI.isEmpty || imageData != nil || !candidates.isEmpty) }

    init(session: AppSession = .shared) { self.session = session }
    func start() {
        active = true
        Task { await reload() }
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        active = false; generation += 1
        timer?.invalidate(); timer = nil
        clearCodes(); material = nil
        candidates = []; secretKey = ""; qrURI = ""; imageData = nil
    }
    func clearCodes() {
        codesGeneration += 1; codes = [:]; expiresAt = 0; countdown = 0; nextCodesAt = 0
    }
    func pageChanged() { clearCodes(); Task { await refreshCodes() } }
    func reload() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; errorText = nil; reviewReady = false; generation += 1
        let token = generation
        defer { if token == generation { isLoading = false } }
        do {
            let rows = try await service.listKeys()
            guard active, token == generation else { return }
            items = rows
            loaded = true; loadFailed = false; reviewReady = requiresReview
            pageState.apply(totalElements: Int64(filtered.count))
            clearCodes()
            await refreshCodes()
        } catch { if active, token == generation { loadFailed = true; errorText = error.localizedDescription } }
    }
    private func tick() {
        guard active else { return }
        guard NSApp.isActive, !adding else {
            if !codes.isEmpty { clearCodes() }
            material = nil
            return
        }
        countdown = max(0, Int(ceil(expiresAt - ProcessInfo.processInfo.systemUptime)))
        if countdown == 0 {
            if !codes.isEmpty { codes = [:] }
            if ProcessInfo.processInfo.systemUptime >= nextCodesAt { Task { await refreshCodes() } }
        }
    }
    private func refreshCodes() async {
        guard active, NSApp.isActive, !adding, !refreshingCodes, !pageItems.isEmpty else { return }
        refreshingCodes = true
        let ids = pageItems.map(\.id), token = codesGeneration
        defer { refreshingCodes = false }
        do {
            let result = try await service.codes(ids: ids)
            guard active, !adding, token == codesGeneration, ids == pageItems.map(\.id), NSApp.isActive else { return }
            codes = result.validFor > 0 ? result.codes : [:]
            expiresAt = ProcessInfo.processInfo.systemUptime + result.validFor
            countdown = max(0, Int(ceil(result.validFor)))
            nextCodesAt = ProcessInfo.processInfo.systemUptime + max(2, result.validFor)
        } catch {
            guard active, token == codesGeneration else { return }
            codes = [:]; errorText = error.localizedDescription
            nextCodesAt = ProcessInfo.processInfo.systemUptime + 30
        }
    }
    func copyCode(_ item: MfaKeyItem) {
        guard ProcessInfo.processInfo.systemUptime < expiresAt, let code = codes[item.id] else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
    }
    func openMaterial(_ item: MfaKeyItem) {
        guard !busy else { return }
        isLoading = true
        let token = generation
        Task {
            do {
                let value = try await service.material(item)
                if active, token == generation, NSApp.isActive { material = value }
            } catch { if active { errorText = error.localizedDescription } }
            isLoading = false
        }
    }
    func openAdd() {
        guard canMutate else { return }
        clearDraft(); clearCodes(); adding = true
    }
    func closeAdd() {
        guard canLeave() else { return }
        clearDraft(); adding = false
    }
    private func clearDraft() {
        keyName = ""; issuer = ""; secretKey = ""; qrURI = ""; imageURL = nil; imageData = nil; imageName = ""
        candidates = []; partialBatch = false; errorText = nil
    }
    func pickImage() {
        guard !busy, !requiresReview else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "gif", "bmp"]
        if panel.runModal() == .OK, let url = panel.url { setImage(url) }
    }
    func setImage(_ url: URL) {
        guard !busy, !requiresReview else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard url.isFileURL, size > 0, size <= 5 * 1024 * 1024 else { throw MfaBackupFailure(message: "二维码图片不能超过 5 MiB") }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024 else { throw MfaBackupFailure(message: "二维码图片不能超过 5 MiB") }
            mode = "image"; imageURL = url; imageData = data; imageName = url.lastPathComponent; candidates = []
        } catch { errorText = error.localizedDescription }
    }
    func pasteImage() {
        guard !busy, !requiresReview else { return }
        let pasteboard = NSPasteboard.general
        let raw = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data = raw, data.count <= 5 * 1024 * 1024,
              let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]),
              png.count <= 5 * 1024 * 1024 else {
            errorText = "剪贴板中没有可用的二维码图片，或图片超过 5 MiB"; return
        }
        mode = "image"; imageURL = nil; imageData = png; imageName = "clipboard.png"; candidates = []
    }
    func preview() {
        guard !busy, !requiresReview else { return }
        isPreviewing = true; errorText = nil
        let snapshot = (mode, keyName, issuer, secretKey, qrURI, imageData)
        Task {
            do {
                let result = try await service.preview(mode: snapshot.0, name: snapshot.1, issuer: snapshot.2,
                    secret: snapshot.3, uri: snapshot.4, image: snapshot.5)
                if active, adding { candidates = result.entries; partialBatch = result.partial }
            } catch { if active { errorText = error.localizedDescription } }
            isPreviewing = false
        }
    }
    func saveCandidates() {
        guard canMutate, !candidates.isEmpty else { return }
        let snapshot = candidates
        guard AppAlert.confirm(title: "保存 MFA 账户", message: "确认添加这 \(snapshot.count) 个账户？同名不同密钥不会覆盖现有账户。", confirmTitle: "保存") else { return }
        isSaving = true; errorText = nil
        Task {
            do {
                let message = try await service.importEntries(snapshot)
                clearDraft(); adding = false; resultText = message
                isSaving = false
                await reload()
            } catch {
                isSaving = false
                errorText = error.localizedDescription
                requiresReview = (error as? MfaBackupFailure)?.writeAttempted ?? true
                if requiresReview { await reload() }
            }
        }
    }
    func delete(_ item: MfaKeyItem) {
        guard canMutate,
              AppAlert.confirm(title: "删除 MFA 账户", message: "确定删除「\(item.keyName)」？", confirmTitle: "删除") else { return }
        isSaving = true; errorText = nil
        Task {
            do {
                try await service.delete(item)
                isSaving = false
                await reload()
            } catch {
                isSaving = false; errorText = error.localizedDescription
                requiresReview = (error as? MfaBackupFailure)?.writeAttempted ?? true
                if requiresReview { await reload() }
            }
        }
    }
    func acknowledgeReview() {
        guard !busy, requiresReview, reviewReady,
              AppAlert.confirm(title: "核对写入结果", message: "请核对服务器中的账户，确认上一操作结果后再继续。", confirmTitle: "已核对") else { return }
        requiresReview = false; reviewReady = false
        clearDraft(); adding = false
        Task { await reload() }
    }
    func exportCSV() {
        guard !busy, !filtered.isEmpty else { return }
        let ids = filtered.map(\.id)
        guard AppAlert.confirm(title: "导出 MFA 账户", message: "将导出全部 \(ids.count) 个搜索匹配账户，包括明文密钥，请妥善保存。", confirmTitle: "导出") else { return }
        isSaving = true
        Task {
            do {
                let data = try await service.exportCSV(ids: ids)
                isSaving = false
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "otp_keys.csv"; panel.allowedFileTypes = ["csv"]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
            } catch { isSaving = false; errorText = error.localizedDescription }
        }
    }
    func canLeave() -> Bool {
        guard !isSaving, !isPreviewing, !requiresReview else { return false }
        return !hasDraft || AppAlert.confirm(title: "放弃添加账户", message: "尚未保存的账户信息将丢失。", confirmTitle: "放弃")
    }
}
