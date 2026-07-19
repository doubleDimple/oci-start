import Foundation
import Combine
import AppKit

@MainActor
final class MfaBackupViewModel: ObservableObject {
    @Published var items: [MfaKeyItem] = []
    @Published var searchText = ""
    @Published var addForm: MfaAddForm?
    @Published var countdown = 30
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorText: String?

    private let session: AppSession
    private var service: MfaBackupService { MfaBackupService(baseURL: session.serverURL) }
    private var timer: Timer?

    var filtered: [MfaKeyItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.keyName.localizedCaseInsensitiveContains(q)
                || $0.issuer.localizedCaseInsensitiveContains(q)
        }
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func start() {
        Task { await reload() }
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await service.listKeys()
            await refreshOtps()
            updateCountdown()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func openAdd() {
        addForm = MfaAddForm()
    }

    func saveAdd() {
        Task { await performSaveAdd() }
    }

    private func performSaveAdd() async {
        guard let form = addForm else { return }
        let name = form.keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = form.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            ToastCenter.shared.error("请填写密钥")
            return
        }
        let keyName = name.isEmpty ? "\(Int(Date().timeIntervalSince1970))" : name
        isSaving = true
        defer { isSaving = false }
        do {
            try await LoadingHUD.shared.during {
                try await service.saveSecret(keyName: keyName, secretKey: secret)
            }
            addForm = nil
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func delete(_ item: MfaKeyItem) {
        let ok = AppAlert.confirm(
            title: "删除密钥",
            message: "确定删除「\(item.keyName)」？",
            confirmTitle: "删除"
        )
        guard ok else { return }
        Task { await performDelete(item) }
    }

    private func performDelete(_ item: MfaKeyItem) async {
        do {
            try await LoadingHUD.shared.during {
                try await service.deleteKey(keyName: item.keyName)
            }
            await reload()
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func toggleSecret(_ item: MfaKeyItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].revealSecret.toggle()
    }

    func copyOtp(_ code: String) {
        guard code.count >= 4, !code.contains("-") else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func exportCSV() {
        Task { await performExport() }
    }

    private func performExport() async {
        do {
            let result = try await LoadingHUD.shared.during {
                try await service.exportCSV()
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = result.1
            panel.allowedFileTypes = ["csv"]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try result.0.write(to: url, options: .atomic)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onTick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func onTick() {
        updateCountdown()
        if countdown == 30 || items.contains(where: { $0.otpCode.contains("-") || $0.otpCode.isEmpty }) {
            Task { await refreshOtps() }
        }
    }

    private func updateCountdown() {
        let sec = Int(Date().timeIntervalSince1970) % 30
        countdown = 30 - sec
    }

    private func refreshOtps() async {
        let secrets = items.map(\.secretKey)
        guard !secrets.isEmpty else { return }
        do {
            let map = try await service.generateOtpBatch(secrets: secrets)
            for i in items.indices {
                if let code = map[items[i].secretKey] {
                    items[i].otpCode = code
                }
            }
        } catch {
            // silent
        }
    }
}
