import SwiftUI

/// 原生备忘管理（对齐 Web `/system/memPage` · `/api/memos`）。
/// 卡片网格遵循质量管理页等宽等高标准。
struct MemoView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MemoViewModel()

    private var dark: Bool { appearance.isDarkEffective }
    private let cardMinHeight: CGFloat = 200

    var body: some View {
        PageScaffold(
            title: "备忘管理",
            subtitle: "本地笔记 · 标题 / 摘要 / 正文",
            systemImage: "book",
            toolbar: { toolbar },
            content: {
                VStack(spacing: 0) {
                    if let err = model.errorText, !err.isEmpty {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    FilterBar {
                        SearchField(text: $model.searchText, placeholder: "搜索标题 / 摘要 / 内容")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ScrollView {
                        if model.filtered.isEmpty && !model.isLoading {
                            EmptyStateView(
                                icon: "book.closed",
                                title: model.items.isEmpty ? "暂无备忘" : "无匹配结果",
                                subtitle: model.items.isEmpty ? "点击「新建备忘」记录内容" : "试试其他关键词",
                                actionTitle: model.items.isEmpty ? "新建备忘" : nil,
                                action: model.items.isEmpty ? { model.openCreate() } : nil
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .padding(16)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(pairRows(model.filtered), id: \.0) { row in
                                    EqualHeightCardRow(minHeight: cardMinHeight) {
                                        memoCard(row.1)
                                    } second: {
                                        if let second = row.2 {
                                            memoCard(second)
                                        } else {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .appLoading(model.isLoading && model.items.isEmpty)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            Task { await model.reload() }
        }
        .sheet(item: $model.activeForm) { _ in
            MemoEditorSheet(model: model)
                .environmentObject(appearance)
        }
        .environmentObject(appearance)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            AppButton(title: "新建备忘", systemImage: "plus", kind: .primary) {
                model.openCreate()
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

    /// 两列配对：(rowIndex, left, right?)
    private func pairRows(_ items: [MemoItem]) -> [(Int, MemoItem, MemoItem?)] {
        var rows: [(Int, MemoItem, MemoItem?)] = []
        var i = 0
        while i < items.count {
            let left = items[i]
            let right = (i + 1 < items.count) ? items[i + 1] : nil
            rows.append((i, left, right))
            i += 2
        }
        return rows
    }

    private func memoCard(_ item: MemoItem) -> some View {
        ModuleSettingsCard(
            title: item.title.isEmpty ? "无标题" : item.title,
            subtitle: item.summary.isEmpty ? "无摘要" : item.summary,
            systemImage: "note.text",
            accent: Color(hex: "4a9eff"),
            enabled: nil,
            minHeight: cardMinHeight
        ) {
            Text(item.content.isEmpty ? "（无正文）" : item.content)
                .font(.system(size: 12))
                .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            if !item.updateTime.isEmpty {
                Text("更新：\(item.updateTime)")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        } footer: {
            HStack(spacing: 8) {
                AppButton(title: "编辑", systemImage: "pencil", kind: .secondary) {
                    model.openEdit(item)
                }
                AppButton(title: "删除", systemImage: "trash", kind: .danger) {
                    model.delete(item)
                }
            }
        }
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

// MARK: - Editor sheet

private struct MemoEditorSheet: View {
    @ObservedObject var model: MemoViewModel
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        AppSheetChrome(
            title: (model.activeForm?.isNew ?? true) ? "新建备忘" : "编辑备忘",
            systemImage: "book",
            width: 560,
            height: 520,
            onClose: { model.activeForm = nil },
            footer: {
                HStack(spacing: 8) {
                    AppButton(title: "取消", kind: .secondary) {
                        model.activeForm = nil
                    }
                    AppButton(
                        title: "保存",
                        systemImage: "square.and.arrow.down",
                        kind: .primary,
                        isLoading: model.isSaving
                    ) {
                        model.saveForm()
                    }
                }
            },
            content: {
                if let binding = formBinding {
                    VStack(alignment: .leading, spacing: 14) {
                        FormFieldRow(label: "标题", required: true) {
                            AppTextField(text: binding.title, placeholder: "备忘标题", leadingSystemImage: "textformat")
                        }
                        FormFieldRow(label: "摘要") {
                            AppTextField(text: binding.summary, placeholder: "可选，最多约 200 字")
                        }
                        FormFieldRow(label: "正文", required: true) {
                            AppTextEditor(text: binding.content, minHeight: 220)
                        }
                    }
                }
            }
        )
    }

    private var formBinding: (
        title: Binding<String>,
        summary: Binding<String>,
        content: Binding<String>
    )? {
        guard model.activeForm != nil else { return nil }
        return (
            Binding(
                get: { model.activeForm?.title ?? "" },
                set: { model.activeForm?.title = $0 }
            ),
            Binding(
                get: { model.activeForm?.summary ?? "" },
                set: { model.activeForm?.summary = $0 }
            ),
            Binding(
                get: { model.activeForm?.content ?? "" },
                set: { model.activeForm?.content = $0 }
            )
        )
    }
}
