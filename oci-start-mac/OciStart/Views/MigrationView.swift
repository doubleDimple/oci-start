import SwiftUI
import AppKit

/// Native data migration (Web: /migration/migPage)
struct MigrationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var busy = false
    @State private var lastMasterKey: String?
    @State private var importKey = ""
    @State private var statusMessage: String?
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL?
    @State private var importIsEncrypted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("数据迁移")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppTheme.text(scheme))

                Text("导出/导入应用数据库备份。导入会覆盖现有数据，请谨慎操作。")
                    .font(.callout)
                    .foregroundColor(AppTheme.muted(scheme))

                // Export
                GroupBox(label: Label("导出", systemImage: "square.and.arrow.up")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { Task { await exportSQL() } }) {
                                Label("导出 SQL", systemImage: "doc.text")
                            }
                            .buttonStyle(ProminentButton())
                            .disabled(busy)

                            Button(action: { Task { await exportEncrypted() } }) {
                                Label("导出加密备份", systemImage: "lock.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                        if let key = lastMasterKey, !key.isEmpty {
                            HStack {
                                Text("Master Key：")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted(scheme))
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(AppTheme.text(scheme))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("复制") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(key, forType: .string)
                                    appState.showToast("Master Key 已复制")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(AppTheme.accent(scheme))
                            }
                            Text("请妥善保存 Master Key，导入加密备份时需要。")
                                .font(.caption2)
                                .foregroundColor(AppTheme.warning)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Import
                GroupBox(label: Label("导入", systemImage: "square.and.arrow.down")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { pickImport(encrypted: false) }) {
                                Label("导入 SQL", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy)

                            Button(action: { pickImport(encrypted: true) }) {
                                Label("导入加密备份", systemImage: "lock.open")
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                        }
                        SecureField("加密导入 Master Key（仅 .enc）", text: $importKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let statusMessage = statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundColor(AppTheme.text(scheme))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.elevated(scheme))
                        .cornerRadius(8)
                }

                if busy {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("处理中…").foregroundColor(AppTheme.muted(scheme))
                    }
                }
            }
            .padding(24)
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("数据迁移")
        .alert(isPresented: $showImportConfirm) {
            Alert(
                title: Text(importIsEncrypted ? "确认导入加密备份" : "确认导入"),
                message: Text(importIsEncrypted
                              ? "导入将覆盖现有数据。请确认 Master Key 正确。"
                              : "导入将覆盖现有数据，是否继续？"),
                primaryButton: .destructive(Text("导入")) {
                    Task { await doImport() }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func exportSQL() async {
        busy = true
        defer { busy = false }
        do {
            let (data, name) = try await appState.network.downloadMigrationExport(baseURL: appState.serverURL)
            try await saveData(data, suggested: name)
            statusMessage = "SQL 导出成功：\(name)"
            appState.showToast("导出成功")
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func exportEncrypted() async {
        busy = true
        defer { busy = false }
        do {
            let (data, name, key) = try await appState.network.downloadMigrationExportEncrypted(baseURL: appState.serverURL)
            lastMasterKey = key
            try await saveData(data, suggested: name)
            statusMessage = "加密备份导出成功：\(name)"
            appState.showToast("加密导出成功")
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func saveData(_ data: Data, suggested: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = suggested
                panel.begin { resp in
                    guard resp == .OK, let url = panel.url else {
                        cont.resume()
                        return
                    }
                    do {
                        try data.write(to: url)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func pickImport(encrypted: Bool) {
        importIsEncrypted = encrypted
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            pendingImportURL = url
            showImportConfirm = true
        }
    }

    private func doImport() async {
        guard let url = pendingImportURL else { return }
        busy = true
        defer { busy = false }
        do {
            let msg: String
            if importIsEncrypted {
                msg = try await appState.network.importMigrationEncrypted(
                    baseURL: appState.serverURL, fileURL: url, masterKey: importKey)
            } else {
                msg = try await appState.network.importMigrationSQL(
                    baseURL: appState.serverURL, fileURL: url)
            }
            statusMessage = msg
            appState.showToast(msg)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
