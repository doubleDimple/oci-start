import SwiftUI
import AppKit

/// 原生 MFA 备份（对齐 Web `/mfa/page`）。
/// 列表区 + 添加表单；视觉对齐质量管理页卡片标准。
struct MfaBackupView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MfaBackupViewModel()

    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(
            title: "MFA 备份",
            subtitle: "TOTP 密钥托管 · 动态验证码 · 导出",
            systemImage: "lock.shield",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    FilterBar {
                        SearchField(text: $model.searchText, placeholder: "搜索名称 / 发行方")
                        Spacer()
                        Text("刷新倒计时 \(model.countdown)s")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if model.filtered.isEmpty && !model.isLoading {
                        EmptyStateView(
                            icon: "lock.shield",
                            title: model.items.isEmpty ? "暂无 MFA 密钥" : "无匹配结果",
                            subtitle: model.items.isEmpty ? "添加密钥后可查看动态验证码" : "试试其他关键词",
                            actionTitle: model.items.isEmpty ? "添加密钥" : nil,
                            action: model.items.isEmpty ? { model.openAdd() } : nil
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(model.filtered) { item in
                                    keyCard(item)
                                }
                            }
                            .padding(16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .appLoading(model.isLoading && model.items.isEmpty)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .sheet(item: $model.addForm) { _ in
            MfaAddSheet(model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "添加密钥", systemImage: "plus", kind: .primary) {
                model.openAdd()
            }
            AppButton(title: "导出 CSV", systemImage: "square.and.arrow.up", kind: .secondary) {
                model.exportCSV()
            }
            AppButton(
                title: "刷新",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isLoading: model.isLoading
            ) {
                Task { await model.reload() }
            }
        }
    }

    private func keyCard(_ item: MfaKeyItem) -> some View {
        HStack(alignment: .center, spacing: 16) {
            if let img = MfaBackupJSON.qrImage(from: item.qrCodeBase64) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 72, height: 72)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border(dark), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "4a9eff").opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "qrcode")
                        .foregroundColor(Color(hex: "4a9eff"))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.keyName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                    Text(item.issuer)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "4a9eff").opacity(0.15))
                        .cornerRadius(6)
                        .foregroundColor(Color(hex: "4a9eff"))
                }
                Button(action: { model.toggleSecret(item) }) {
                    Text(item.revealSecret ? item.secretKey : "••••••••••••")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.sidebarText(dark))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Button(action: { model.copyOtp(item.otpCode) }) {
                    Text(item.otpCode)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(dark ? Color.white : Color.primary)
                }
                .buttonStyle(PlainButtonStyle())
                Text("点击复制 · \(model.countdown)s")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
            .frame(minWidth: 100)

            AppButton(title: "删除", systemImage: "trash", kind: .danger) {
                model.delete(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.sidebarBg(dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.18 : 0.05), radius: 8, y: 2)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "f85149"))
            Text(text).font(.system(size: 12))
            Spacer()
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(Color(hex: "f85149"))
        .padding(12)
        .background(Color(hex: "f85149").opacity(0.1))
        .cornerRadius(8)
    }
}

private struct MfaAddSheet: View {
    @ObservedObject var model: MfaBackupViewModel
    @EnvironmentObject private var appearance: AppearanceController

    var body: some View {
        AppSheetChrome(
            title: "添加 MFA 密钥",
            systemImage: "lock.shield",
            width: 480,
            height: 320,
            onClose: { model.addForm = nil },
            footer: {
                HStack(spacing: 8) {
                    AppButton(title: "取消", kind: .secondary) {
                        model.addForm = nil
                    }
                    AppButton(
                        title: "保存",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isLoading: model.isSaving
                    ) {
                        model.saveAdd()
                    }
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    FormFieldRow(label: "名称") {
                        AppTextField(
                            text: Binding(
                                get: { model.addForm?.keyName ?? "" },
                                set: { model.addForm?.keyName = $0 }
                            ),
                            placeholder: "留空则用时间戳",
                            leadingSystemImage: "tag"
                        )
                    }
                    FormFieldRow(label: "密钥", required: true) {
                        AppTextField(
                            text: Binding(
                                get: { model.addForm?.secretKey ?? "" },
                                set: { model.addForm?.secretKey = $0 }
                            ),
                            placeholder: "Base32 Secret",
                            leadingSystemImage: "key"
                        )
                    }
                    Text("也可后续扩展二维码导入；当前支持手动填写密钥。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.sidebarText(appearance.isDarkEffective))
                }
            }
        )
    }
}
