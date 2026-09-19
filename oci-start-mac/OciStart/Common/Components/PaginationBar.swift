import SwiftUI

/// Native equivalent of Vue PagePagination; the server page remains zero based.
struct PaginationBar: View {
    @Binding var state: PageState
    var showsSizeSelector: Bool = true
    var showsJump: Bool = false
    var rangeTextOverride: String? = nil
    var disabled: Bool = false
    var onChange: () -> Void = {}

    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var appearance: AppearanceController
    @State private var compact = false
    @State private var jumpText = ""
    private var dark: Bool { appearance.isDarkEffective }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width < 680 {
                    VStack(alignment: .leading, spacing: 10) {
                        summary
                        controls(compact: true)
                    }
                } else {
                    HStack(spacing: 10) {
                        summary
                        Spacer(minLength: 10)
                        controls(compact: false)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .onAppear { compact = proxy.size.width < 680 }
            .onChange(of: proxy.size.width) { compact = $0 < 680 }
        }
        .frame(height: compact ? 86 : 56)
        .background(AppTheme.cardBg(dark))
        .overlay(Rectangle().fill(AppTheme.border(dark).opacity(0.4)).frame(height: 1), alignment: .top)
        .disabled(disabled)
        .accessibilityLabel(language.text("分页", "Pagination"))
    }

    private var summary: some View {
        Text(rangeTextOverride ?? language.text("共 \(state.totalElements) 条", "\(state.totalElements) records"))
            .font(.system(size: AppTheme.secondarySize))
            .foregroundColor(AppTheme.textSecondary(dark))
            .lineLimit(1)
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if showsSizeSelector {
                SelectMenu(options: PageState.sizeOptions.map {
                    SelectOption(id: "\($0)", title: language.text("\($0) 条/页", "\($0) / page"))
                }, selection: Binding(get: { "\(state.size)" }, set: { value in
                    guard !disabled, let value = value, let size = Int(value), size != state.size else { return }
                    state.changeSize(size)
                    onChange()
                }), placeholder: language.text("\(state.size) 条/页", "\(state.size) / page"),
                   width: compact ? 112 : 128, allowClear: false, searchable: false)
                    .padding(.trailing, 8)
            }
            arrow("chevron.left", label: language.text("上一页", "Previous page"), unavailable: state.isFirst) {
                state.goPrev(); onChange()
            }
            if compact {
                number(state.page)
            } else {
                ForEach(visiblePages, id: \.self) { page in
                    if page < 0 {
                        Text("…").frame(width: 24, height: 32)
                            .foregroundColor(AppTheme.textSecondary(dark))
                    } else {
                        number(page)
                    }
                }
            }
            arrow("chevron.right", label: language.text("下一页", "Next page"), unavailable: state.isLast) {
                state.goNext(); onChange()
            }
            if showsJump {
                AppCompactField(text: $jumpText, placeholder: "\(state.displayPage)", width: 48, height: 32, onCommit: jump)
                    .accessibilityLabel(language.text("跳至页码", "Go to page"))
            }
        }
        .font(.system(size: AppTheme.bodySize))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func number(_ page: Int) -> some View {
        Button {
            guard !disabled, page != state.page else { return }
            state.go(to: page)
            onChange()
        } label: {
            Text("\(page + 1)")
                .font(.system(size: AppTheme.bodySize, weight: page == state.page ? .semibold : .regular))
                .foregroundColor(page == state.page ? .white : AppTheme.textPrimary(dark))
                .frame(minWidth: 32, minHeight: 32)
                .background(page == state.page ? AppTheme.sidebarActive : AppTheme.inputBg(dark))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(language.text("第 \(page + 1) 页", "Page \(page + 1)"))
    }

    private func arrow(_ symbol: String, label: String, unavailable: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(dark))
                .frame(width: 32, height: 32)
                .background(AppTheme.inputBg(dark))
                .cornerRadius(8)
                .opacity(unavailable ? 0.35 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(unavailable || disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private var visiblePages: [Int] {
        let total = max(1, state.totalPages)
        if total <= 5 { return Array(0..<total) }
        let start = max(1, min(state.page - 1, total - 4))
        let end = min(total - 2, max(state.page + 1, 3))
        return [0] + (start > 1 ? [-1] : []) + Array(start...end)
            + (end < total - 2 ? [-2] : []) + [total - 1]
    }

    private func jump() {
        guard !disabled, let page = Int(jumpText.trimmingCharacters(in: .whitespaces)), page > 0 else { return }
        let old = state.page
        state.go(to: page - 1)
        jumpText = ""
        if old != state.page { onChange() }
    }
}
