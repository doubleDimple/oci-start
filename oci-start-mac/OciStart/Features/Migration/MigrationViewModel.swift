import Foundation
import Combine
import AppKit

@MainActor
final class MigrationViewModel: ObservableObject {
    @Published var masterKeyInput = ""
    @Published private(set) var selectedFileName: String?
    @Published private(set) var artifact: MigrationExportResult?
    @Published private(set) var receipt: MigrationImportReceipt?
    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false
    @Published private(set) var errorText: String?
    @Published private(set) var outcome: MigrationFailure.Outcome?
    @Published private(set) var backupSaved = false
    @Published private(set) var keySaved = false
    @Published var savedAcknowledged = false
    private var selectedData: Data?
    private var selectedServer = ""
    private let session: AppSession
    var busy: Bool { isExporting || isImporting }
    var requiresReview: Bool { outcome == .unknown }
    var hasUnsavedExport: Bool { artifact != nil && !savedAcknowledged }
    var canImport: Bool { selectedData != nil && !masterKeyInput.isEmpty && !busy && !requiresReview && receipt == nil }

    init(session: AppSession = .shared) { self.session = session }

    func pickImportFile() {
        guard !busy, !requiresReview else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["enc"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectFile(url)
    }

    func selectFile(_ url: URL) {
        guard !busy, !requiresReview else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard url.pathExtension.lowercased() == "enc", size > 0, size <= MigrationJSON.maxBackupBytes else {
                throw MigrationFailure(message: "请选择不超过 10 MiB 的 .enc 备份文件", outcome: .rejected)
            }
            let snapshot = try Data(contentsOf: url)
            try MigrationJSON.validateEnvelope(snapshot)
            selectedData = snapshot; selectedFileName = url.lastPathComponent
            selectedServer = session.serverURL
            errorText = nil; outcome = nil; receipt = nil
        } catch { errorText = error.localizedDescription }
    }

    func clearImportFile() {
        guard !busy, !requiresReview else { return }
        selectedData = nil; selectedFileName = nil; masterKeyInput = ""
        errorText = nil; outcome = nil; receipt = nil
    }

    func exportEncrypted() {
        guard !busy, !requiresReview else { return }
        if hasUnsavedExport && !AppAlert.confirm(title: "重新生成备份", message: "当前备份和密钥尚未确认保存，继续将替换它们。", confirmTitle: "继续") { return }
        isExporting = true; errorText = nil
        let service = MigrationService(baseURL: session.serverURL)
        Task {
            do {
                let result = try await service.exportEncrypted()
                artifact = result; backupSaved = false; keySaved = false; savedAcknowledged = false
            } catch { errorText = error.localizedDescription }
            isExporting = false
        }
    }

    func saveBackup() {
        guard let value = artifact, !busy else { return }
        backupSaved = save(value.data, name: value.filename, type: "enc") || backupSaved
    }

    func saveKey() {
        guard let value = artifact, !busy else { return }
        keySaved = save(Data(value.masterKey.utf8), name: "oci-start_migration_master-key.txt", type: "txt") || keySaved
    }

    private func save(_ data: Data, name: String, type: String) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true; panel.nameFieldStringValue = name; panel.allowedFileTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try data.write(to: url, options: .atomic); return true }
        catch { errorText = error.localizedDescription; return false }
    }

    func importEncrypted() {
        guard canImport, let snapshot = selectedData else { return }
        let key: String
        do { key = try MigrationJSON.normalizeKey(masterKeyInput) }
        catch { errorText = error.localizedDescription; return }
        guard session.serverURL == selectedServer else {
            errorText = "服务器已更改，请重新选择备份文件"; return
        }
        guard AppAlert.confirm(title: "确认导入", message: "目标服务器：\(selectedServer)\n备份：\(selectedFileName ?? "")\n\n请确认已备份目标服务器，并在维护期间导入。将保留目标同名系统配置；其他主键冲突会拒绝整批导入。", confirmTitle: "已备份，开始导入") else { return }
        isImporting = true; errorText = nil; outcome = nil
        let service = MigrationService(baseURL: selectedServer)
        Task {
            do {
                receipt = try await service.importEncrypted(data: snapshot, masterKey: key)
                selectedData = nil; selectedFileName = nil; masterKeyInput = ""
            } catch {
                let failure = error as? MigrationFailure
                outcome = failure?.outcome ?? .unknown
                errorText = error.localizedDescription
            }
            isImporting = false
        }
    }

    func acknowledgeReview() {
        guard requiresReview, !busy,
              AppAlert.confirm(title: "核对导入结果", message: "请先在服务器端核对本次导入是否已经提交，确认后才可开始新的操作。", confirmTitle: "已在服务器核对") else { return }
        outcome = nil
        clearImportFile()
    }

    func canLeave() -> Bool {
        guard !busy, !requiresReview else { return false }
        guard hasUnsavedExport || selectedData != nil || !masterKeyInput.isEmpty else { return true }
        return AppAlert.confirm(title: "离开数据迁移", message: "未保存的备份、密钥和导入草稿将丢失，是否离开？", confirmTitle: "离开")
    }
}
