import SwiftUI
import AppKit

/// Native tabbed flow matching Vue MigrationView.
struct MigrationView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MigrationViewModel()
    @ObservedObject private var language = LanguageManager.shared
    @State private var importing = false
    @State private var revealKey = false
    @State private var guardOwner = UUID()
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(title: "数据迁移", toolbar: {
            HStack(spacing: 12) {
                tab(language.text("数据导出", "Export"), selected: !importing) { importing = false }
                tab(language.text("数据导入", "Import"), selected: importing) { importing = true }
                Spacer()
                if let error = model.errorText { PageErrorIndicator(message: error) }
            }
        }, content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if importing { importContent } else { exportContent }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        })
        .onAppear { NavigationState.shared.setLeaveGuard(owner: guardOwner) { model.canLeave() } }
        .onDisappear { NavigationState.shared.removeLeaveGuard(owner: guardOwner) }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? AppTheme.sidebarActive : AppTheme.textSecondary(dark))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? AppTheme.sidebarActive.opacity(0.1) : Color.clear).cornerRadius(8)
        }.buttonStyle(PlainButtonStyle()).disabled(model.busy || model.requiresReview)
    }

    private var exportContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language.text(model.artifact == nil ? "导出加密备份" : "加密备份已生成", model.artifact == nil ? "Export encrypted backup" : "Backup generated"))
                .font(.system(size: AppTheme.sectionSize, weight: .semibold))
            Text(language.text("导出业务数据并单独保存解密密钥。", "Export business data and save the decryption key separately."))
                .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
            if let artifact = model.artifact {
                Text(artifact.filename).font(.system(size: 14))
                Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.data.count), countStyle: .file))
                    .font(.system(size: 13))
                AppButton(title: language.text("保存备份文件", "Save backup"), systemImage: "square.and.arrow.down", kind: .secondary) { model.saveBackup() }
                Divider()
                Text("Master Key").font(.system(size: 14, weight: .semibold))
                HStack {
                    Text(revealKey ? artifact.masterKey : String(repeating: "•", count: 24))
                        .font(.system(size: 14, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Button(action: { revealKey.toggle() }) { Image(systemName: revealKey ? "eye.slash" : "eye") }
                        .buttonStyle(PlainButtonStyle()).help(language.text("显示或隐藏密钥", "Show or hide key"))
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(artifact.masterKey, forType: .string)
                    }) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(PlainButtonStyle()).help(language.text("复制密钥", "Copy key"))
                }
                AppButton(title: language.text("保存密钥文件", "Save key"), systemImage: "key", kind: .secondary) { model.saveKey() }
                Toggle(language.text("我已分别保存备份文件和密钥", "I saved both the backup and its key"), isOn: $model.savedAcknowledged)
                    .toggleStyle(CheckboxToggleStyle()).font(.system(size: 14))
            }
            AppButton(title: language.text(model.artifact == nil ? "生成加密备份" : "重新生成", model.artifact == nil ? "Generate backup" : "Regenerate"),
                      systemImage: "lock", kind: .primary, isLoading: model.isExporting) { model.exportEncrypted() }
                .disabled(model.busy || model.requiresReview)
        }
    }

    private var importContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language.text(model.receipt == nil ? "导入加密备份" : "导入完成", model.receipt == nil ? "Import encrypted backup" : "Import complete"))
                .font(.system(size: 16, weight: .semibold))
            if let receipt = model.receipt {
                Text(language.text("新增 \(receipt.importedRows) 条 · 保留 \(receipt.preservedRows) 条", "\(receipt.importedRows) imported · \(receipt.preservedRows) preserved"))
                    .font(.system(size: 14))
                HStack { Text(language.text("数据表", "Table")); Spacer(); Text(language.text("新增 / 保留", "Imported / preserved")) }
                    .font(.system(size: 14, weight: .semibold))
                ForEach(receipt.tables) { row in
                    HStack { Text(row.table); Spacer(); Text("\(row.importedRows) / \(row.preservedRows)") }.font(.system(size: 14))
                }
                AppButton(title: language.text("完成", "Done"), kind: .secondary) { model.clearImportFile() }
            } else {
                Text(language.text("选择 .enc 文件并输入对应的 Master Key。", "Choose an .enc file and enter its Master Key."))
                    .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                HStack {
                    Image(systemName: "doc.badge.arrow.up")
                    Text(model.selectedFileName ?? language.text("选择或拖入加密备份（最大 10 MiB）", "Choose or drop a backup (up to 10 MiB)"))
                        .lineLimit(2)
                    Spacer()
                    AppButton(title: language.text("选择文件", "Choose file"), kind: .secondary) { model.pickImportFile() }
                }
                .font(.system(size: 14)).padding(20)
                .background(AppTheme.inputBg(dark)).cornerRadius(12)
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    guard !model.busy, !model.requiresReview, let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url { DispatchQueue.main.async { model.selectFile(url) } }
                    }
                    return true
                }
                FormFieldRow(label: "Master Key", required: true) {
                    AppTextField(text: $model.masterKeyInput, placeholder: language.text("备份的解密密钥", "Backup decryption key"), secure: true)
                }
                .disabled(model.busy || model.requiresReview)
                if model.requiresReview {
                    Text(language.text("导入结果未知，需先在服务器核对。", "Import outcome is unknown. Review the server before continuing."))
                        .font(.system(size: 14)).foregroundColor(AppTheme.warning(dark))
                    AppButton(title: language.text("已在服务器核对结果", "Confirm server review"), kind: .secondary) { model.acknowledgeReview() }
                } else {
                    if model.outcome == .rolledBack {
                        Text(language.text("本次导入已回滚。", "This import was rolled back.")).font(.system(size: 13))
                    }
                    HStack {
                        AppButton(title: language.text("开始导入", "Import"), systemImage: "tray.and.arrow.down", kind: .primary, isLoading: model.isImporting) { model.importEncrypted() }
                            .disabled(!model.canImport)
                        AppButton(title: language.text("清除", "Clear"), kind: .secondary) { model.clearImportFile() }.disabled(model.busy)
                    }
                }
            }
        }
    }
}
