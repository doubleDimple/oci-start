import SwiftUI
import AppKit

/// 原生数据迁移（对齐 Web `/migration/migPage`）。
/// UI 标准：两列 `ModuleSettingsCard` 等宽等高。
struct MigrationView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MigrationViewModel()

    private var dark: Bool { appearance.isDarkEffective }
    private let cardMinHeight: CGFloat = 360

    var body: some View {
        PageScaffold(
            title: "数据迁移",
            subtitle: "加密导出备份 · 导入恢复",
            systemImage: "arrow.left.and.right",
            toolbar: { EmptyView() },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        EqualHeightCardRow(minHeight: cardMinHeight) {
                            exportCard
                        } second: {
                            importCard
                        }
                        if let key = model.lastMasterKey, !key.isEmpty {
                            masterKeyBanner(key)
                        }
                        if let status = model.statusText, !status.isEmpty {
                            Text(status)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.sidebarText(dark))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .environmentObject(appearance)
    }

    private var exportCard: some View {
        ModuleSettingsCard(
            title: "数据导出",
            subtitle: "生成加密 .enc 备份",
            systemImage: "square.and.arrow.up",
            accent: Color(hex: "4a9eff"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            infoLine(icon: "lock.shield", text: "导出为加密备份文件，密钥仅显示一次。")
            infoLine(icon: "1.circle", text: "点击「导出加密备份」下载 .enc 文件")
            infoLine(icon: "2.circle", text: "务必单独保存 Master Key，导入时需要")
            infoLine(icon: "exclamationmark.triangle", text: "密钥丢失将无法解密恢复")
        } footer: {
            AppButton(
                title: "导出加密备份",
                systemImage: "lock",
                kind: .primary,
                isLoading: model.isExporting
            ) {
                model.exportEncrypted()
            }
        }
    }

    private var importCard: some View {
        ModuleSettingsCard(
            title: "数据导入",
            subtitle: "上传 .enc 并填写密钥",
            systemImage: "square.and.arrow.down",
            accent: Color(hex: "1abc9c"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            FormFieldRow(label: "备份文件") {
                HStack(spacing: 8) {
                    Text(model.selectedFileName ?? "未选择文件")
                        .font(.system(size: 12))
                        .foregroundColor(
                            model.selectedFileName == nil
                                ? AppTheme.sidebarText(dark)
                                : (dark ? Color.white.opacity(0.9) : Color.primary)
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AppButton(title: "选择", systemImage: "folder", kind: .secondary) {
                        model.pickImportFile()
                    }
                    if model.selectedFileName != nil {
                        AppButton(title: "清除", kind: .secondary) {
                            model.clearImportFile()
                        }
                    }
                }
            }
            FormFieldRow(label: "Master Key") {
                AppTextField(
                    text: $model.masterKeyInput,
                    placeholder: "加密备份的解密密钥",
                    secure: true,
                    leadingSystemImage: "key"
                )
            }
            Text("导入会覆盖当前库中相关数据，操作前请确认已备份。")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            AppButton(
                title: "开始导入",
                systemImage: "tray.and.arrow.down",
                kind: .primary,
                isLoading: model.isImporting
            ) {
                model.importEncrypted()
            }
        }
    }

    private func infoLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "4a9eff"))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func masterKeyBanner(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近一次导出的 Master Key")
                .font(.system(size: 12, weight: .semibold))
            Text(key)
                .font(.system(size: 12, design: .monospaced))
            HStack {
                Spacer()
                AppButton(title: "复制密钥", systemImage: "doc.on.doc", kind: .secondary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(key, forType: .string)
                }
            }
        }
        .foregroundColor(dark ? Color.white.opacity(0.9) : Color.primary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "f0881a").opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "f0881a").opacity(0.35), lineWidth: 1)
        )
    }
}
