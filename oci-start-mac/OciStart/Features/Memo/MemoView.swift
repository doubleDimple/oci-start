import SwiftUI
import AppKit

/// Native table, reader and full-page rich editor for the current Vue memo flow.
struct MemoView: View {
    @EnvironmentObject private var appearance: AppearanceController
    @StateObject private var model = MemoViewModel()
    @ObservedObject private var language = LanguageManager.shared
    @State private var guardOwner = UUID()
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        PageScaffold(title: "笔记", toolbar: { toolbar }, content: {
            VStack(spacing: 0) {
                notices
                if model.screen == .list { list }
                else if model.screen == .read { reading }
                else { editor }
            }
        }, footer: { footer })
        .onAppear {
            model.start()
            NavigationState.shared.setLeaveGuard(owner: guardOwner) { model.canLeave() }
        }
        .onDisappear {
            model.stop()
            NavigationState.shared.removeLeaveGuard(owner: guardOwner)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ociReloadCurrentPage)) { _ in
            if model.screen == .edit {
                model.back()
                guard model.screen != .edit else { return }
            }
            Task { await model.reload() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if model.screen == .list { NavigationState.shared.select(.dashboard) }
                else { model.back() }
            }) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(PlainButtonStyle())
            .help(language.text("返回", "Back"))
            .disabled(model.isSaving || model.requiresReview)
            if model.screen == .list {
                SearchField(text: $model.searchText, placeholder: language.text("搜索标题 / 摘要 / 内容", "Search title, summary, or content"), maxWidth: 340)
                    .frame(width: 280)
                    .disabled(model.isSaving)
            } else {
                Text(language.text(model.screen == .read ? "查看笔记" : model.activeForm?.isNew == true ? "新建笔记" : "编辑笔记",
                                   model.screen == .read ? "Read note" : model.activeForm?.isNew == true ? "New note" : "Edit note"))
                    .font(.system(size: 14, weight: .medium))
            }
            Spacer(minLength: 8)
            if let message = model.errorText ?? model.detailError ?? model.mutationError {
                PageErrorIndicator(message: message, retry: model.isSaving ? nil : { model.recheck() })
            }
            if model.screen == .edit {
                AppButton(title: language.text("清空", "Clear"), systemImage: "eraser", kind: .secondary,
                          enabled: !model.editorDisabled) { model.clearEditor() }
            } else {
                AppButton(title: language.text("刷新", "Refresh"), systemImage: "arrow.clockwise", kind: .secondary,
                          isLoading: model.isLoading || model.detailLoading, enabled: !model.isSaving) {
                    Task { await model.reload() }
                }
                if model.screen == .list {
                    AppButton(title: language.text("新建笔记", "New note"), systemImage: "plus", enabled: model.canMutate) { model.openCreate() }
                } else {
                    AppButton(title: language.text("删除", "Delete"), systemImage: "trash", kind: .secondary,
                              enabled: model.canMutate && model.detailReady) { model.deleteCurrent() }
                    AppButton(title: language.text("编辑", "Edit"), systemImage: "pencil",
                              enabled: model.canMutate && model.detailReady) { model.editCurrent() }
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if model.requiresReview {
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("提交结果尚未确认。草稿已保留，请对照重新读取的笔记；不要重复提交。", "The write result is uncertain. Your draft is retained. Compare the reloaded notes before submitting again."))
                    .font(.system(size: 14))
                HStack(spacing: 10) {
                    AppButton(title: language.text("重新读取", "Recheck"), systemImage: "arrow.clockwise", kind: .secondary,
                              enabled: !model.isSaving && !model.isLoading && !model.detailLoading) { model.recheck() }
                    AppButton(title: language.text("已核对结果", "I reviewed the result"), systemImage: "checkmark", kind: .secondary,
                              enabled: model.reviewReady) { model.acknowledgeReview() }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.statusBg(AppTheme.warning(dark), dark))
        } else if let feedback = model.feedback {
            HStack {
                Text(feedback).font(.system(size: 14))
                Spacer()
                Button(action: { model.clearFeedback() }) { Image(systemName: "xmark") }
                    .buttonStyle(PlainButtonStyle()).help(language.text("关闭", "Dismiss"))
            }
            .padding(14).foregroundColor(AppTheme.success)
            .background(AppTheme.statusBg(AppTheme.success, dark))
        }
    }

    private var list: some View {
        GeometryReader { proxy in
            NativeHorizontalTable(contentWidth: max(820, proxy.size.width), viewportWidth: proxy.size.width, height: proxy.size.height) {
                table
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(language.text("笔记", "Note")).frame(maxWidth: .infinity, alignment: .leading)
                Text(language.text("创建时间", "Created")).frame(width: 150, alignment: .leading)
                Text(language.text("更新时间", "Updated")).frame(width: 150, alignment: .leading)
                Text(language.text("操作", "Actions")).frame(width: 170, alignment: .leading)
            }
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(AppTheme.cardSubtle(dark))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleItems) { item in row(item) }
                    if model.visibleItems.isEmpty && !model.isLoading {
                        EmptyStateView(icon: "note.text", title: language.text(model.errorText != nil ? "笔记加载失败" : model.searchText.isEmpty ? "暂无笔记" : "无匹配结果",
                                                                            model.errorText != nil ? "Could not load notes" : model.searchText.isEmpty ? "No notes yet" : "No matching notes"),
                                       subtitle: language.text(model.errorText != nil ? "请使用工具栏重新读取。" : "在这里记录文字、链接和图片。",
                                                               model.errorText != nil ? "Reload from the toolbar." : "Keep text, links, and images here."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appLoading(model.isLoading && model.items.isEmpty)
        }
    }

    private func row(_ item: MemoItem) -> some View {
        HStack(spacing: 12) {
            Button(action: { model.open(item) }) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title.isEmpty ? language.text("无标题", "Untitled") : item.title)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text((item.summary.isEmpty ? item.content : item.summary).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(PlainButtonStyle()).disabled(model.isSaving || model.requiresReview)
            Text(date(item.createTime)).font(.system(size: 13)).frame(width: 150, alignment: .leading)
            Text(date(item.updateTime)).font(.system(size: 13)).frame(width: 150, alignment: .leading)
            HStack(spacing: 12) {
                rowAction("查看", "View", icon: "eye", enabled: !model.isSaving && !model.requiresReview) { model.open(item) }
                rowAction("编辑", "Edit", icon: "pencil", enabled: model.canMutate) { model.open(item, edit: true) }
                rowAction("删除", "Delete", icon: "trash", enabled: model.canMutate, danger: true) { model.open(item, remove: true) }
            }.frame(width: 170, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .bottom)
    }

    private func rowAction(_ zh: String, _ en: String, icon: String, enabled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Text(language.text(zh, en)).font(.system(size: 13))
            }
            .foregroundColor(danger ? AppTheme.danger : AppTheme.textPrimary(dark))
        }
        .buttonStyle(PlainButtonStyle()).disabled(!enabled)
        .accessibilityLabel(language.text(zh, en))
    }

    private var reading: some View {
        VStack(spacing: 0) {
            if let item = model.detail {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title).font(.system(size: 18, weight: .semibold))
                    HStack(spacing: 22) {
                        Text(language.text("创建：", "Created: ") + date(item.createTime))
                        Text(language.text("更新：", "Updated: ") + date(item.updateTime))
                        Text(language.text("服务器本地时间", "Server local time"))
                    }.font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                    if !item.summary.isEmpty { Text(item.summary).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                MemoNativeReader(item: item).id(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.detailLoading {
                PageLoadingView(message: language.text("正在读取笔记…", "Loading note…"))
            } else {
                EmptyStateView(icon: "note.text", title: model.detailError ?? language.text("未选择笔记", "No note selected"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appLoading(model.detailLoading && model.detail == nil)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FormFieldRow(label: language.text("标题", "Title"), required: true) {
                    AppTextField(text: Binding(get: { model.activeForm?.title ?? "" }, set: { model.activeForm?.title = $0 }),
                                 placeholder: language.text("笔记标题", "Note title"))
                }
                .disabled(model.editorDisabled)
                FormFieldRow(label: language.text("摘要", "Summary")) {
                    AppTextEditor(text: Binding(get: { model.activeForm?.summary ?? "" }, set: { model.activeForm?.summary = $0 }), minHeight: 62)
                    Text("\(model.activeForm?.summary.utf16.count ?? 0) / 200")
                        .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                }
                .disabled(model.editorDisabled)
                if let form = model.activeForm {
                    MemoRichEditor(form: form, disabled: model.editorDisabled, onChange: { text, html in
                        model.updateDocument(text: text, html: html)
                    })
                        .id(model.editorID)
                        .frame(minHeight: 340)
                }
                if let error = model.mutationError {
                    Text(error).font(.system(size: 14)).foregroundColor(AppTheme.danger)
                }
                if model.showSavedVersion { comparison }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var comparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("最新保存版本", "Latest saved version")).font(.system(size: 16, weight: .semibold))
            if model.activeForm?.id != nil {
                if let item = model.detail {
                    Text(item.title).font(.system(size: 14, weight: .semibold))
                    if !item.summary.isEmpty { Text(item.summary).font(.system(size: 13)) }
                    MemoNativeReader(item: item).id(item).frame(height: 200)
                    AppButton(title: language.text("使用已保存版本", "Use saved version"), kind: .secondary,
                              enabled: !model.requiresReview && model.detailReady && !model.isSaving) { model.useSavedVersion() }
                } else {
                    Text(model.detailError ?? language.text("笔记不存在", "The note no longer exists")).font(.system(size: 14))
                }
                AppButton(title: language.text("将草稿另存为新笔记", "Keep draft as a new note"), kind: .secondary,
                          enabled: model.canMutate) { model.keepAsNew() }
            } else {
                Text(language.text("请核对列表，确认刚才的新建是否已经保存。", "Review the list to check whether the new note was saved.")).font(.system(size: 13))
                SearchField(text: $model.searchText, placeholder: language.text("搜索核对笔记", "Search notes to review"))
                ForEach(model.visibleItems) { item in
                    DisclosureGroup("\(item.title) · #\(item.id) · \(date(item.createTime))") {
                        MemoNativeReader(item: item).id(item).frame(height: 180)
                    }
                }
                PaginationBar(state: $model.page, showsSizeSelector: false, disabled: model.isSaving)
            }
        }
        .padding(16).background(AppTheme.cardSubtle(dark)).cornerRadius(12)
    }

    @ViewBuilder private var footer: some View {
        if model.screen == .list {
            PaginationBar(state: $model.page, showsSizeSelector: false,
                          rangeTextOverride: language.text("显示 \(model.filtered.count) / 共 \(model.items.count) 条笔记", "\(model.filtered.count) of \(model.items.count) notes"),
                          disabled: model.isSaving)
        } else {
            HStack {
                Text(model.screen == .edit
                     ? language.text(model.isSaving ? "正在提交…" : model.dirty ? "有未保存的修改" : "⌘ Return 保存", model.isSaving ? "Submitting…" : model.dirty ? "Unsaved changes" : "⌘ Return to save")
                     : model.detail.map { "#\($0.id)" } ?? "—")
                    .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary(dark))
                Spacer()
                if model.screen == .edit {
                    AppButton(title: language.text("保存", "Save"), systemImage: "square.and.arrow.down",
                              isLoading: model.isSaving, enabled: model.canSave) { model.saveForm() }
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(Rectangle().fill(AppTheme.border(dark)).frame(height: 1), alignment: .top)
        }
    }

    private func date(_ value: String) -> String {
        // Server values carry no offset; never convert them to the Mac time zone.
        value.isEmpty ? "—" : String(value.replacingOccurrences(of: "T", with: " ").prefix(16))
    }
}

private struct MemoNativeReader: View {
    let item: MemoItem
    @StateObject private var controller = MemoEditorController()
    @EnvironmentObject private var appearance: AppearanceController

    var body: some View {
        MemoNativeTextView(form: MemoFormState(item: item), editable: false, dark: appearance.isDarkEffective,
                           controller: controller, onChange: { _, _ in })
            .background(AppTheme.cardBg(appearance.isDarkEffective))
    }
}

private struct MemoRichEditor: View {
    let form: MemoFormState
    let disabled: Bool
    let onChange: (String, String) -> Void
    @StateObject private var controller = MemoEditorController()
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var appearance: AppearanceController
    @State private var selectedBlock: String? = "p"
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    SelectMenu(options: [
                        SelectOption(id: "p", title: language.text("正文", "Paragraph")),
                        SelectOption(id: "h1", title: language.text("标题 1", "Heading 1")),
                        SelectOption(id: "h2", title: language.text("标题 2", "Heading 2")),
                        SelectOption(id: "h3", title: language.text("标题 3", "Heading 3")),
                        SelectOption(id: "blockquote", title: language.text("引用", "Quote")),
                        SelectOption(id: "pre", title: language.text("代码块", "Code block"))
                    ], selection: Binding(get: { selectedBlock }, set: { value in selectedBlock = value; controller.block(value ?? "p") }),
                       placeholder: language.text("正文", "Paragraph"), width: 140, allowClear: false, searchable: false)
                    tool("bold", "加粗", "Bold") { controller.trait(.boldFontMask) }
                    tool("italic", "斜体", "Italic") { controller.trait(.italicFontMask) }
                    tool("underline", "下划线", "Underline") { controller.toggle(.underlineStyle) }
                    tool("strikethrough", "删除线", "Strikethrough") { controller.toggle(.strikethroughStyle) }
                    tool("list.bullet", "无序列表", "Bullet list") { controller.block("ul") }
                    tool("list.number", "有序列表", "Numbered list") { controller.block("ol") }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    tool("link", "插入链接", "Insert link") { controller.insertLink() }
                    tool("photo", "插入图片", "Insert image") { controller.insertImage() }
                    tool("textformat", "清除格式", "Clear formatting") { controller.clearFormatting() }
                    tool("arrow.uturn.backward", "撤销", "Undo") { controller.undo() }
                    tool("arrow.uturn.forward", "重做", "Redo") { controller.redo() }
                    Spacer(minLength: 0)
                    Text(language.text("点击图片后加载预览", "Click an image to load its preview"))
                        .font(.system(size: 12)).foregroundColor(AppTheme.textSecondary(dark))
                }
            }
            .padding(8).background(AppTheme.inputBg(dark)).disabled(disabled)
            Rectangle().fill(AppTheme.border(dark)).frame(height: 1)
            MemoNativeTextView(form: form, editable: !disabled, dark: dark, controller: controller, onChange: onChange)
                .frame(minHeight: 260)
        }
        .background(AppTheme.cardBg(dark)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderStrong(dark)))
    }

    private func tool(_ icon: String, _ zh: String, _ en: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 16)).frame(width: 32, height: 32) }
            .buttonStyle(PlainButtonStyle()).help(language.text(zh, en)).accessibilityLabel(language.text(zh, en))
    }
}

// MARK: - Native rich document (no HTML/WebView resource loading)

private extension NSAttributedString.Key {
    static let memoPath = NSAttributedString.Key("OciMemoBlockPath")
    static let memoBlockIDs = NSAttributedString.Key("OciMemoBlockIDs")
    static let memoSeparator = NSAttributedString.Key("OciMemoBlockSeparator")
    static let memoEmpty = NSAttributedString.Key("OciMemoEmptyBlock")
    static let memoImage = NSAttributedString.Key("OciMemoImageSource")
    static let memoAlt = NSAttributedString.Key("OciMemoImageAlt")
    static let memoTitle = NSAttributedString.Key("OciMemoImageTitle")
    static let memoLinkTitle = NSAttributedString.Key("OciMemoLinkTitle")
}

private enum MemoNativeDocument {
    static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "blockquote", "pre", "ul", "ol", "li"]
    static let ignoredTags: Set<String> = ["script", "style", "iframe", "object", "embed", "link", "meta", "head"]

    static func decode(html: String?, text: String, dark: Bool) -> NSAttributedString {
        guard let html = html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let document = try? XMLDocument(xmlString: "<html><body>\(html)</body></html>",
                                             options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let body = (try? document.nodes(forXPath: "//body"))?.first else {
            return NSAttributedString(string: text, attributes: attributes(path: ["p"], dark: dark))
        }
        let output = NSMutableAttributedString(string: "")
        var lastSynthetic = false
        func separator(_ attrs: [NSAttributedString.Key: Any]) {
            guard output.length > 0, !output.string.hasSuffix("\n") else { return }
            var separatorAttributes = attrs
            separatorAttributes.removeValue(forKey: .memoEmpty)
            separatorAttributes[.memoSeparator] = true
            output.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
            lastSynthetic = true
        }
        func visit(_ node: XMLNode, path: [String], ids: [String], inherited: [NSAttributedString.Key: Any]) {
            if node.kind == .text {
                let text = node.stringValue ?? ""
                if !text.isEmpty { output.append(NSAttributedString(string: text, attributes: inherited)); lastSynthetic = false }
                return
            }
            guard let element = node as? XMLElement else {
                node.children?.forEach { visit($0, path: path, ids: ids, inherited: inherited) }; return
            }
            let tag = (element.name ?? "").lowercased()
            guard !ignoredTags.contains(tag) else { return }
            var path = path, ids = ids, attrs = inherited
            let block = blockTags.contains(tag)
            if block {
                separator(inherited)
                path.append(tag)
                ids.append(UUID().uuidString)
                let base = attributes(path: path, dark: dark)
                attrs[.memoPath] = path
                attrs[.memoBlockIDs] = ids
                attrs[.paragraphStyle] = base[.paragraphStyle]
                if ["h1", "h2", "h3", "pre"].contains(tag), let baseFont = base[.font] as? NSFont {
                    attrs[.font] = preservingTraits(baseFont, from: attrs[.font] as? NSFont)
                }
            }
            if ["strong", "b", "em", "i"].contains(tag) {
                let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: ["strong", "b"].contains(tag) ? .boldFontMask : .italicFontMask)
            }
            if tag == "code" {
                attrs[.font] = preservingTraits(NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), from: attrs[.font] as? NSFont)
            }
            if tag == "u" { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if ["s", "strike"].contains(tag) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if tag == "a", let href = safeURL(element.attribute(forName: "href")?.stringValue ?? "") {
                attrs[.link] = href
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let title = element.attribute(forName: "title")?.stringValue { attrs[.memoLinkTitle] = title }
            }
            let start = output.length
            if tag == "br" {
                output.append(NSAttributedString(string: "\n", attributes: attrs)); lastSynthetic = false
            } else if tag == "img" {
                let alt = element.attribute(forName: "alt")?.stringValue ?? ""
                if let source = safeURL(element.attribute(forName: "src")?.stringValue ?? "", image: true) {
                    output.append(image(source: source, alt: alt, title: element.attribute(forName: "title")?.stringValue, attrs: attrs))
                } else { output.append(NSAttributedString(string: alt, attributes: attrs)) }
                lastSynthetic = false
            } else {
                element.children?.forEach { visit($0, path: path, ids: ids, inherited: attrs) }
            }
            if block, output.length == start {
                // An invisible, typed metadata character retains an empty block.
                // It is stripped from clipboard text and saved text/HTML.
                var empty = attrs
                empty[.memoEmpty] = true
                empty[.font] = NSFont.systemFont(ofSize: 0.1)
                empty[.foregroundColor] = NSColor.clear
                output.append(NSAttributedString(string: "\u{200b}", attributes: empty))
            }
            if block { separator(attrs) }
        }
        let initial = attributes(path: [], dark: dark)
        body.children?.forEach { visit($0, path: [], ids: [], inherited: initial) }
        if lastSynthetic, output.length > 0 { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        return output
    }

    static func preservingTraits(_ font: NSFont, from previous: NSFont?) -> NSFont {
        guard let previous = previous else { return font }
        let traits = NSFontManager.shared.traits(of: previous).intersection([.boldFontMask, .italicFontMask])
        return traits.isEmpty ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)
    }

    static func attributes(path: [String], dark: Bool) -> [NSAttributedString.Key: Any] {
        let heading = path.last(where: { ["h1", "h2", "h3"].contains($0) })
        let size: CGFloat = heading == "h3" ? 16 : heading == nil ? 14 : 18
        let font = path.contains("pre") ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            : NSFont.systemFont(ofSize: size, weight: heading == nil ? .regular : .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        if path.contains("blockquote") { paragraph.headIndent += 14; paragraph.firstLineHeadIndent += 14 }
        let listDepth = path.filter { $0 == "ul" || $0 == "ol" }.count
        paragraph.headIndent += CGFloat(listDepth * 22)
        paragraph.firstLineHeadIndent += CGFloat(listDepth * 22)
        paragraph.paragraphSpacing = 7
        if let list = path.last(where: { $0 == "ul" || $0 == "ol" }) {
            paragraph.textLists = [NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: list == "ol" ? "{decimal}." : "{disc}"), options: 0)]
        }
        return [.font: font, .foregroundColor: NSColor(AppTheme.textPrimary(dark)), .paragraphStyle: paragraph,
                .memoPath: path, .memoBlockIDs: path.map { _ in UUID().uuidString }]
    }

    static func encode(_ attributed: NSAttributedString) -> (text: String, html: String) {
        var html = "", plain = ""
        var open: [String] = [], openIDs: [String] = []
        var lastPlainSynthetic = false
        func transition(_ wanted: [String], ids: [String]) {
            var common = 0
            while common < min(open.count, wanted.count), open[common] == wanted[common],
                  openIDs[common] == ids[common] { common += 1 }
            for tag in open.dropFirst(common).reversed() { html += "</\(tag)>" }
            for tag in wanted.dropFirst(common) { html += "<\(tag)>" }
            open = wanted
            openIDs = ids
        }
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            let value = (attributed.string as NSString).substring(with: range)
            var path = (attrs[.memoPath] as? [String] ?? ["p"]).filter { blockTags.contains($0) }
            if path.isEmpty { path = ["p"] }
            let storedIDs = attrs[.memoBlockIDs] as? [String] ?? []
            let ids = storedIDs.count == path.count ? storedIDs : path
            transition(path, ids: ids)
            if attrs[.memoSeparator] as? Bool == true {
                if !plain.isEmpty && !plain.hasSuffix("\n") { plain += "\n"; lastPlainSynthetic = true }
                if NSMaxRange(range) == attributed.length {
                    var nextIDs = ids
                    nextIDs[nextIDs.count - 1] = UUID().uuidString
                    transition(path, ids: nextIDs)
                }
                return
            }
            if attrs[.memoEmpty] as? Bool == true { return }
            if let source = attrs[.memoImage] as? String {
                let alt = attrs[.memoAlt] as? String ?? ""
                if !alt.isEmpty { plain += alt; lastPlainSynthetic = false }
                var imageHTML = "<img src=\"\(escaped(source))\" alt=\"\(escaped(alt))\""
                if let title = attrs[.memoTitle] as? String { imageHTML += " title=\"\(escaped(title))\"" }
                imageHTML += ">"
                html += linked(imageHTML, attributes: attrs)
                return
            }
            if !value.isEmpty {
                plain += value.replacingOccurrences(of: "\u{2028}", with: "\n")
                lastPlainSynthetic = false
            }
            html += inlineHTML(value, attributes: attrs, path: path)
        }
        transition([], ids: [])
        if lastPlainSynthetic && plain.hasSuffix("\n") { plain.removeLast() }
        return (plain, html)
    }

    private static func inlineHTML(_ text: String, attributes: [NSAttributedString.Key: Any], path: [String]) -> String {
        var run = escaped(text).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { run = "<strong>\(run)</strong>" }
            if traits.contains(.italicFontMask) { run = "<em>\(run)</em>" }
            if traits.contains(.fixedPitchFontMask) && !path.contains("pre") { run = "<code>\(run)</code>" }
        }
        if ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0 { run = "<u>\(run)</u>" }
        if ((attributes[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0 { run = "<s>\(run)</s>" }
        return linked(run, attributes: attributes)
    }

    private static func linked(_ content: String, attributes: [NSAttributedString.Key: Any]) -> String {
        guard let value = attributes[.link], let href = safeURL(String(describing: value)) else { return content }
        let title = (attributes[.memoLinkTitle] as? String).map { " title=\"\(escaped($0))\"" } ?? ""
        return "<a href=\"\(escaped(href))\"\(title)>\(content)</a>"
    }

    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func safeURL(_ raw: String, image: Bool = false) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"), !value.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }) else { return nil }
        if image, value.range(of: "^data:image/(png|jpeg|gif|webp);base64,[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil { return value }
        guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if !image && scheme == "mailto" && !url.path.isEmpty { return value }
        guard ["http", "https"].contains(scheme), !(url.host ?? "").isEmpty, url.user == nil, url.password == nil,
              !image || url.fragment == nil else { return nil }
        return value
    }

    static func image(source: String, alt: String, title: String? = nil, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let placeholder = NSImage(size: NSSize(width: 190, height: 36), flipped: false) { rect in
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
            let label = alt.isEmpty ? LanguageManager.shared.text("图片 · 点击预览", "Image · click to preview") : alt
            (label as NSString).draw(in: rect.insetBy(dx: 8, dy: 9), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            return true
        }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: placeholder)
        let result = NSMutableAttributedString(attachment: attachment)
        var attributes = attrs
        attributes.removeValue(forKey: .memoSeparator)
        attributes.removeValue(forKey: .memoEmpty)
        attributes[.memoImage] = source
        attributes[.memoAlt] = alt
        if let title = title { attributes[.memoTitle] = title }
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }
}

private final class MemoEditorController: ObservableObject {
    weak var editor: MemoNSTextView?
    var publish: (() -> Void)?
    private var language: LanguageManager { .shared }

    private func edit(_ transform: (NSMutableAttributedString, NSRange) -> Void) {
        guard let editor = editor, editor.isEditable, let storage = editor.textStorage else { return }
        let range = editor.selectedRange()
        guard range.location <= storage.length else { return }
        let before = NSAttributedString(attributedString: storage)
        editor.undoManager?.registerUndo(withTarget: editor) { target in target.restore(before) }
        storage.beginEditing()
        transform(storage, range)
        storage.endEditing()
        editor.window?.makeFirstResponder(editor)
        editor.setSelectedRange(range)
        publish?()
    }

    func trait(_ trait: NSFontTraitMask) {
        guard let editor = editor, editor.isEditable else { return }
        if editor.selectedRange().length == 0 {
            let font = editor.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let active = NSFontManager.shared.traits(of: font).contains(trait)
            editor.typingAttributes[.font] = active ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
            editor.window?.makeFirstResponder(editor)
            return
        }
        edit { storage, range in
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let remove = NSFontManager.shared.traits(of: font).contains(trait)
            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let old = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
                storage.addAttribute(.font, value: remove ? NSFontManager.shared.convert(old, toNotHaveTrait: trait) : NSFontManager.shared.convert(old, toHaveTrait: trait), range: subrange)
            }
        }
    }

    func toggle(_ key: NSAttributedString.Key) {
        guard let editor = editor, editor.isEditable else { return }
        if editor.selectedRange().length == 0 {
            editor.typingAttributes[key] = ((editor.typingAttributes[key] as? NSNumber)?.intValue ?? 0) == 0 ? 1 : 0
            editor.window?.makeFirstResponder(editor)
            return
        }
        edit { storage, range in
            let old = (storage.attribute(key, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            storage.addAttribute(key, value: old == 0 ? 1 : 0, range: range)
        }
    }

    func block(_ tag: String) {
        guard let editor = editor, editor.isEditable else { return }
        let path = tag == "ul" || tag == "ol" ? [tag, "li"] : [tag]
        let attrs = MemoNativeDocument.attributes(path: path, dark: AppearanceController.shared.isDarkEffective)
        if editor.string.isEmpty { editor.typingAttributes = attrs; editor.window?.makeFirstResponder(editor); return }
        edit { storage, selection in
            let range = (storage.string as NSString).paragraphRange(for: selection)
            let containerID = UUID().uuidString
            var position = range.location
            while position < NSMaxRange(range) {
                let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: position, length: 0))
                var blockAttributes = attrs
                blockAttributes[.memoBlockIDs] = path.count == 2 ? [containerID, UUID().uuidString] : [UUID().uuidString]
                blockAttributes.removeValue(forKey: .font)
                storage.addAttributes(blockAttributes, range: paragraph)
                storage.enumerateAttribute(.font, in: paragraph, options: []) { value, fontRange, _ in
                    let base = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
                    storage.addAttribute(.font, value: MemoNativeDocument.preservingTraits(base, from: value as? NSFont), range: fontRange)
                }
                let last = NSMaxRange(paragraph) - 1
                if (storage.string as NSString).substring(with: NSRange(location: last, length: 1)) == "\n" {
                    storage.addAttribute(.memoSeparator, value: true, range: NSRange(location: last, length: 1))
                }
                position = NSMaxRange(paragraph)
            }
        }
    }

    func clearFormatting() {
        guard let editor = editor, editor.isEditable else { return }
        if editor.selectedRange().length == 0 {
            var attrs = editor.typingAttributes
            let path = attrs[.memoPath] as? [String] ?? ["p"]
            attrs[.font] = MemoNativeDocument.attributes(path: path, dark: AppearanceController.shared.isDarkEffective)[.font]
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .link, .memoLinkTitle] { attrs.removeValue(forKey: key) }
            editor.typingAttributes = attrs
            return
        }
        edit { storage, range in
            storage.enumerateAttribute(.memoPath, in: range, options: []) { value, fontRange, _ in
                let path = value as? [String] ?? ["p"]
                if let font = MemoNativeDocument.attributes(path: path, dark: AppearanceController.shared.isDarkEffective)[.font] {
                    storage.addAttribute(.font, value: font, range: fontRange)
                }
            }
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.link, range: range)
            storage.removeAttribute(.memoLinkTitle, range: range)
        }
    }

    func insertLink() {
        guard let editor = editor, editor.isEditable else { return }
        guard let raw = AppAlert.prompt(title: language.text("插入链接", "Insert link"),
                                        message: language.text("输入 HTTP、HTTPS 或 mailto 链接。", "Enter an HTTP, HTTPS, or mailto link."), placeholder: "https://"),
              let href = MemoNativeDocument.safeURL(raw) else { return }
        if editor.selectedRange().length == 0 {
            var attrs = editor.typingAttributes
            attrs[.link] = href
            attrs[.underlineStyle] = 1
            editor.insertText(NSAttributedString(string: href, attributes: attrs), replacementRange: editor.selectedRange())
        } else {
            edit { storage, range in storage.addAttributes([.link: href, .underlineStyle: 1], range: range) }
        }
        publish?()
    }

    func insertImage() {
        guard let editor = editor, editor.isEditable else { return }
        guard let raw = AppAlert.prompt(title: language.text("插入图片", "Insert image"),
                                        message: language.text("输入图片的 HTTP / HTTPS 地址，图片只在点击预览后加载。", "Enter an HTTP / HTTPS image URL. Images load only after clicking their preview."), placeholder: "https://"),
              let source = MemoNativeDocument.safeURL(raw, image: true),
              let alt = AppAlert.prompt(title: language.text("图片说明", "Image description"),
                                        message: language.text("输入图片说明（可留空）。", "Describe the image (optional).")) else { return }
        editor.insertText(MemoNativeDocument.image(source: source, alt: alt, attrs: editor.typingAttributes),
                          replacementRange: editor.selectedRange())
        publish?()
    }

    func undo() { editor?.undoManager?.undo(); publish?() }
    func redo() { editor?.undoManager?.redo(); publish?() }
}

private final class MemoNSTextView: NSTextView {
    var publish: (() -> Void)?
    var applyingAppearance = false
    var currentTextColor: NSColor?

    func cleanTypingAttributes() {
        var attributes = typingAttributes
        for key in [NSAttributedString.Key.memoSeparator, .memoEmpty, .memoImage, .memoAlt, .memoTitle, .attachment] {
            attributes.removeValue(forKey: key)
        }
        let path = attributes[.memoPath] as? [String] ?? ["p"]
        if let font = attributes[.font] as? NSFont, font.pointSize < 1 {
            attributes[.font] = MemoNativeDocument.attributes(path: path, dark: AppearanceController.shared.isDarkEffective)[.font]
        }
        typingAttributes = attributes
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        cleanTypingAttributes()
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        guard isEditable else { return }
        cleanTypingAttributes()
        let insertion = selectedRange().location
        let old = typingAttributes
        super.insertNewline(sender)
        guard let storage = textStorage, insertion < storage.length else { return }
        storage.addAttribute(.memoSeparator, value: true, range: NSRange(location: insertion, length: 1))
        var next = old
        let path = old[.memoPath] as? [String] ?? ["p"]
        var ids = old[.memoBlockIDs] as? [String] ?? path.map { _ in UUID().uuidString }
        if ids.isEmpty { ids = [UUID().uuidString] } else { ids[ids.count - 1] = UUID().uuidString }
        next[.memoBlockIDs] = ids
        next.removeValue(forKey: .memoSeparator)
        next.removeValue(forKey: .memoEmpty)
        let position = selectedRange().location
        if position < storage.length {
            let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: position, length: 0))
            storage.addAttribute(.memoBlockIDs, value: ids, range: paragraph)
        }
        typingAttributes = next
        publish?()
    }

    override func insertLineBreak(_ sender: Any?) {
        guard isEditable else { return }
        insertText("\n", replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        insertPasteboard(NSPasteboard.general)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        // Use the same local HTML sanitizer for drops; never let AppKit import
        // remote resources through RTFD or file attachments.
        return insertPasteboard(sender.draggingPasteboard)
    }

    @discardableResult private func insertPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let plain = pasteboard.string(forType: .string) ?? ""
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            let content = MemoNativeDocument.decode(html: html, text: plain, dark: AppearanceController.shared.isDarkEffective)
            insertText(content, replacementRange: selectedRange())
            return true
        }
        guard pasteboard.string(forType: .string) != nil else { return false }
        insertText(plain, replacementRange: selectedRange())
        return true
    }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let value = MemoNativeDocument.encode(attributedString().attributedSubstring(from: selectedRange()))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value.text, forType: .string)
        NSPasteboard.general.setString(value.html, forType: .html)
    }

    func restore(_ content: NSAttributedString) {
        guard let storage = textStorage else { return }
        let current = NSAttributedString(attributedString: storage)
        undoManager?.registerUndo(withTarget: self) { target in target.restore(current) }
        storage.setAttributedString(content)
        publish?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let manager = layoutManager, let container = textContainer, let storage = textStorage {
            let index = manager.characterIndex(for: NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y),
                                               in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            if index < storage.length, let source = storage.attribute(.memoImage, at: index, effectiveRange: nil) as? String {
                let glyphRange = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                if rect.contains(point) { previewImage(source); return }
            }
        }
        super.mouseDown(with: event)
    }

    private func previewImage(_ source: String) {
        guard MemoNativeDocument.safeURL(source, image: true) != nil else { return }
        let language = LanguageManager.shared
        Task { @MainActor in
            do {
                let data: Data
                if source.hasPrefix("data:"), let comma = source.firstIndex(of: ","),
                   let decoded = Data(base64Encoded: String(source[source.index(after: comma)...])) { data = decoded }
                else {
                    guard let url = URL(string: source) else { return }
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpCookieStorage = nil
                    configuration.httpShouldSetCookies = false
                    let session = URLSession(configuration: configuration)
                    defer { session.invalidateAndCancel() }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 30
                    let result = try await session.compatData(for: request)
                    guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw MemoFailure(key: .requestFailed) }
                    data = result.0
                }
                guard let image = NSImage(data: data) else { throw MemoFailure(key: .invalidResponse) }
                let alert = NSAlert()
                alert.messageText = language.text("图片预览", "Image preview")
                let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
                view.image = image
                view.imageScaling = .scaleProportionallyUpOrDown
                alert.accessoryView = view
                alert.addButton(withTitle: language.text("关闭", "Close"))
                alert.runModal()
            } catch { AppAlert.error(message: language.text("图片加载失败。", "Could not load the image.")) }
        }
    }
}

private struct MemoNativeTextView: NSViewRepresentable {
    let form: MemoFormState
    let editable: Bool
    let dark: Bool
    let controller: MemoEditorController
    let onChange: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = MemoNSTextView(frame: scroll.bounds)
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.textStorage?.setAttributedString(MemoNativeDocument.decode(html: form.htmlContent, text: form.content, dark: dark))
        editor.typingAttributes = MemoNativeDocument.attributes(path: ["p"], dark: dark)
        scroll.documentView = editor
        controller.editor = editor
        let publish = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor = editor, let coordinator = coordinator, editor.isEditable, !editor.applyingAppearance else { return }
            let value = MemoNativeDocument.encode(editor.attributedString())
            coordinator.parent.onChange(value.text, value.html)
        }
        controller.publish = publish
        editor.publish = publish
        apply(editor, scroll: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? MemoNSTextView else { return }
        apply(editor, scroll: scroll)
    }

    private func apply(_ editor: MemoNSTextView, scroll: NSScrollView) {
        editor.applyingAppearance = true
        defer { editor.applyingAppearance = false }
        let color = NSColor(AppTheme.cardBg(dark))
        scroll.drawsBackground = true
        scroll.backgroundColor = color
        editor.backgroundColor = color
        editor.isEditable = editable
        editor.isSelectable = true
        editor.insertionPointColor = NSColor(AppTheme.textPrimary(dark))
        editor.linkTextAttributes = [.foregroundColor: NSColor(AppTheme.textPrimary(dark)), .underlineStyle: 1]
        let textColor = NSColor(AppTheme.textPrimary(dark))
        if editor.currentTextColor?.isEqual(textColor) != true, let storage = editor.textStorage {
            storage.enumerateAttribute(.memoEmpty, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
                storage.addAttribute(.foregroundColor, value: value as? Bool == true ? NSColor.clear : textColor, range: range)
            }
            editor.currentTextColor = textColor
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MemoNativeTextView
        init(_ parent: MemoNativeTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) { (notification.object as? MemoNSTextView)?.publish?() }
        func textViewDidChangeSelection(_ notification: Notification) { (notification.object as? MemoNSTextView)?.cleanTypingAttributes() }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let string = MemoNativeDocument.safeURL(String(describing: link)), let url = URL(string: string) else { return true }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}
