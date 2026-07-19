import Foundation
import Combine
import AppKit

@MainActor
final class MigrationViewModel: ObservableObject {
    @Published var masterKeyInput = ""
    @Published var selectedFileName: String?
    @Published private(set) var selectedFileURL: URL?
    @Published private(set) var lastMasterKey: String?
    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false
    @Published private(set) var statusText: String?

    private let session: AppSession
    private var service: MigrationService { MigrationService(baseURL: session.serverURL) }

    init(session: AppSession = .shared) {
        self.session = session
    }

    func pickImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["enc", "sql"]
        panel.message = "选择备份文件（.enc 加密备份）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        statusText = nil
    }

    func clearImportFile() {
        selectedFileURL = nil
        selectedFileName = nil
    }

    func exportEncrypted() {
        Task { await performExport() }
    }

    private func performExport() async {
        isExporting = true
        statusText = nil
        defer { isExporting = false }
        do {
            let result = try await LoadingHUD.shared.during {
                try await service.exportEncrypted()
            }
            lastMasterKey = result.masterKey
            try saveToDownloads(data: result.data, suggestedName: result.filename)
            if let key = result.masterKey, !key.isEmpty {
                AppAlert.info(
                    title: "导出成功 · 请妥善保存密钥",
                    message: "加密备份已保存。\n\nMaster Key（只显示一次）：\n\(key)\n\n导入时需要此密钥。"
                )
            } else {
                AppAlert.info(title: "导出成功", message: "加密备份已保存。")
            }
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func importEncrypted() {
        Task { await performImport() }
    }

    private func performImport() async {
        guard let fileURL = selectedFileURL else {
            ToastCenter.shared.error("请先选择备份文件")
            return
        }
        let key = masterKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileURL.pathExtension.lowercased() == "enc", key.isEmpty {
            ToastCenter.shared.error("加密备份请填写 Master Key")
            return
        }
        let ok = AppAlert.confirm(
            title: "确认导入",
            message: "导入将覆盖当前数据库中的对应数据，请确认已做好备份。",
            confirmTitle: "导入"
        )
        guard ok else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let msg = try await LoadingHUD.shared.during {
                try await service.importEncrypted(
                    fileURL: fileURL,
                    masterKey: key.isEmpty ? nil : key
                )
            }
            statusText = msg
            AppAlert.info(title: "导入完成", message: msg)
        } catch {
            ToastCenter.shared.error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func saveToDownloads(data: Data, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.allowedFileTypes = ["enc"]
        panel.message = "保存加密备份"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw APIError.serverMessage("已取消保存")
        }
        try data.write(to: url, options: .atomic)
    }
}
