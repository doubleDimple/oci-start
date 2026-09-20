import SwiftUI
import AppKit

struct MfaBackupView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MfaBackupViewModel()
    @ObservedObject private var language = LanguageManager.shared
    @State private var guardOwner = UUID()
    @State private var revealSecret = false
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(title: "MFA 备份", toolbar: {
            HStack(spacing: 10) {
                if model.adding {
                    AppButton(title: language.text("返回", "Back"), systemImage: "chevron.left", kind: .secondary) { model.closeAdd() }
                    Spacer()
                    if !model.candidates.isEmpty {
                        AppButton(title: language.text("保存账户", "Save accounts"), kind: .primary, isLoading: model.isSaving) { model.saveCandidates() }
                            .disabled(!model.canMutate)
                    }
                } else {
                    SearchField(text: $model.searchText, placeholder: language.text("搜索名称 / 发行者", "Search name / issuer"), maxWidth: 280)
                        .frame(width: 240)
                    Spacer()
                    AppButton(title: language.text("导出 CSV", "Export CSV"), kind: .secondary) { model.exportCSV() }.disabled(model.busy || model.filtered.isEmpty)
                    AppButton(title: language.text("刷新", "Refresh"), systemImage: "arrow.clockwise", kind: .secondary) { Task { await model.reload() } }.disabled(model.busy)
                    AppButton(title: language.text("添加账户", "Add account"), systemImage: "plus", kind: .primary) { model.openAdd() }.disabled(!model.canMutate)
                }
                if let error = model.errorText { PageErrorIndicator(message: error) }
            }
        }, content: {
            VStack(spacing: 0) {
                if model.requiresReview {
                    HStack {
                        Text(language.text("操作结果待核对", "Review the previous operation")).font(.system(size: 13))
                        Spacer()
                        AppButton(title: language.text("重新读取", "Reload"), kind: .secondary, enabled: !model.busy) { Task { await model.reload() } }
                        AppButton(title: language.text("已核对服务器结果", "Confirm server review"), kind: .secondary) { model.acknowledgeReview() }
                            .disabled(model.busy || !model.reviewReady)
                    }.padding(16)
                }
                if model.adding { editor } else { list }
            }
            .appLoading(model.isLoading && model.items.isEmpty)
        }, footer: {
            if !model.adding {
                PaginationBar(state: Binding(get: {
                    var page = model.pageState
                    page.apply(totalElements: Int64(model.filtered.count))
                    return page
                }, set: { model.pageState = $0 }), showsSizeSelector: false, disabled: model.busy) { model.pageChanged() }
            }
        })
        .onAppear {
            model.start()
            NavigationState.shared.setLeaveGuard(owner: guardOwner) { model.canLeave() }
        }
        .onDisappear { NavigationState.shared.removeLeaveGuard(owner: guardOwner); model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            if !model.adding { Task { await model.reload() } }
        }
        .sheet(item: $model.material) { item in
            AppSheetChrome(title: item.keyName, systemImage: "qrcode", width: 480, height: 460,
                onClose: { model.material = nil; revealSecret = false },
                footer: { AppButton(title: language.text("关闭", "Close"), kind: .secondary) { model.material = nil; revealSecret = false } },
                content: {
                    VStack(spacing: 20) {
                        if let image = MfaBackupJSON.qrImage(from: item.qrCode) {
                            Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 180, height: 180)
                        }
                        Text(item.issuer.isEmpty ? "—" : item.issuer).font(.system(size: 14))
                        HStack {
                            Text(revealSecret ? item.secretKey : String(repeating: "•", count: 20))
                                .font(.system(size: 14, design: .monospaced))
                            Button(action: { revealSecret.toggle() }) { Image(systemName: revealSecret ? "eye.slash" : "eye") }.buttonStyle(PlainButtonStyle())
                            Button(action: {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.secretKey, forType: .string)
                            }) { Image(systemName: "doc.on.doc") }.buttonStyle(PlainButtonStyle())
                        }
                    }.frame(maxWidth: .infinity)
                }).environmentObject(appearance)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let result = model.resultText { Text(result).font(.system(size: 13)).padding(.horizontal, 18).padding(.bottom, 10) }
            if model.filtered.isEmpty && !model.isLoading {
                EmptyStateView(icon: "lock.shield", title: language.text("暂无匹配账户", "No matching accounts"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    NativeHorizontalTable(contentWidth: max(840, geometry.size.width), viewportWidth: geometry.size.width, height: geometry.size.height) {
                        accountTable
                    }
                }
            }
        }
    }

    private var accountTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(language.text("账户 / 发行者", "Account / issuer")).frame(maxWidth: .infinity, alignment: .leading)
                Text(language.text("验证码", "Code")).frame(width: 130, alignment: .leading)
                Text(language.text("创建时间", "Created")).frame(width: 160, alignment: .leading)
                Text(language.text("操作", "Actions")).frame(width: 140, alignment: .trailing)
            }.lineLimit(1).font(.system(size: 14, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.pageItems) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.keyName).font(.system(size: 14))
                                Text(item.issuer.isEmpty ? "—" : item.issuer).font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: { model.copyCode(item) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.codes[item.id] ?? "—").font(.system(size: 16, weight: .medium, design: .monospaced))
                                    Text(model.countdown > 0 ? "\(model.countdown)s" : "—").font(.system(size: 13))
                                }.frame(width: 130, alignment: .leading)
                            }.buttonStyle(PlainButtonStyle()).disabled(model.codes[item.id] == nil)
                                .help(language.text("复制当前验证码", "Copy current code"))
                            Text(item.createTime.isEmpty ? "—" : item.createTime).font(.system(size: 13)).frame(width: 160, alignment: .leading)
                            HStack(spacing: 12) {
                                Button(language.text("密钥 / QR", "Key / QR")) { revealSecret = false; model.openMaterial(item) }
                                Button(language.text("删除", "Delete")) { model.delete(item) }.foregroundColor(AppTheme.danger).disabled(!model.canMutate)
                            }.font(.system(size: 14)).buttonStyle(PlainButtonStyle()).frame(width: 140, alignment: .trailing).disabled(model.busy || model.requiresReview)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(language.text("添加 MFA 账户", "Add MFA accounts")).font(.system(size: 16, weight: .semibold))
                if model.candidates.isEmpty {
                    SelectMenu(options: [
                        SelectOption(id: "manual", title: language.text("手动输入", "Manual entry")),
                        SelectOption(id: "image", title: language.text("二维码图片", "QR image")),
                        SelectOption(id: "uri", title: language.text("二维码文本", "QR text"))
                    ], selection: Binding(get: { model.mode }, set: { if let mode = $0 { model.mode = mode } }),
                    width: 200, allowClear: false, searchable: false)
                    if model.mode == "manual" {
                        FormFieldRow(label: language.text("名称", "Name"), required: true) { AppTextField(text: $model.keyName, placeholder: language.text("账户名称", "Account name")) }
                        FormFieldRow(label: language.text("发行者", "Issuer")) { AppTextField(text: $model.issuer, placeholder: language.text("可选", "Optional")) }
                        FormFieldRow(label: language.text("密钥", "Secret"), required: true) { AppTextField(text: $model.secretKey, placeholder: "Base32", secure: true) }
                    } else if model.mode == "uri" {
                        FormFieldRow(label: language.text("二维码文本", "QR text"), required: true) {
                            AppTextEditor(text: $model.qrURI, minHeight: 120)
                        }
                        AppButton(title: language.text("粘贴二维码文本", "Paste QR text"), kind: .secondary) {
                            model.qrURI = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                    } else {
                        Text(model.imageName.isEmpty ? language.text("选择二维码图片（最大 5 MiB）", "Choose a QR image (up to 5 MiB)") : model.imageName).font(.system(size: 14))
                        AppButton(title: language.text("选择图片", "Choose image"), systemImage: "photo", kind: .secondary) { model.pickImage() }
                            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                                guard let provider = providers.first, !model.busy else { return false }
                                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                    if let url = url { DispatchQueue.main.async { model.setImage(url) } }
                                }
                                return true
                            }
                        AppButton(title: language.text("粘贴二维码图片", "Paste QR image"), systemImage: "doc.on.clipboard", kind: .secondary) { model.pasteImage() }
                    }
                    AppButton(title: language.text("预览账户", "Preview accounts"), kind: .primary, isLoading: model.isPreviewing) { model.preview() }.disabled(model.busy || model.requiresReview)
                } else {
                    if model.partialBatch {
                        Text(language.text("这是多张迁移二维码中的一部分，其余二维码需分别导入。", "This is part of a multi-code migration. Import the remaining QR codes separately."))
                            .font(.system(size: 13)).foregroundColor(AppTheme.warning(dark))
                    }
                    ForEach(Array(model.candidates.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            FormFieldRow(label: language.text("账户名称", "Account name"), required: true) {
                                AppTextField(text: Binding(get: { model.candidates[index].keyName }, set: { model.candidates[index].keyName = $0 }), placeholder: "")
                            }
                            Text(model.candidates[index].issuer.isEmpty ? "—" : model.candidates[index].issuer).font(.system(size: 13))
                            Text(String(repeating: "•", count: 20)).font(.system(size: 14, design: .monospaced))
                        }.padding(16).background(AppTheme.inputBg(dark)).cornerRadius(12)
                    }
                    AppButton(title: language.text("重新填写", "Edit input"), kind: .secondary) { model.candidates = [] }
                }
            }
            .disabled(model.isSaving || model.requiresReview)
            .padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
