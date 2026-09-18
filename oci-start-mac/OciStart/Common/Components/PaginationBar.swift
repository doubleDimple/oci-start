import SwiftUI

/// Drop-in pagination bar (Web `pagination.ftl`, 0-based page).
///
/// ```swift
/// PaginationBar(state: $model.pageState) {
///     model.reload()   // or apply slice
/// }
/// ```
///
/// - Page size: shared `SelectMenu`
/// - Jump field: `AppCompactField` / `AppInputStyle` (no system focus ring)
struct PaginationBar: View {
    @Binding var state: PageState
    /// 是否显示每页条数选择（token 游标分页等场景可关）
    var showsSizeSelector: Bool = true
    /// 是否显示跳转输入
    var showsJump: Bool = true
    /// 覆盖默认 `rangeText`（例如「共 100+ 条」）
    var rangeTextOverride: String? = nil
    var onChange: () -> Void = {}

    @State private var jumpText: String = ""
    @State private var compactLayout = false

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    private let controlHeight: CGFloat = 32
    private let compactWidth: CGFloat = 800
    private var rowHeight: CGFloat { max(controlHeight, AppInputStyle.height) }

    private var sizeOptions: [SelectOption] {
        PageState.sizeOptions.map { SelectOption(id: "\($0)", title: "\($0)") }
    }

    private var sizeSelection: Binding<String?> {
        Binding(
            get: { "\(state.size)" },
            set: { newVal in
                guard let raw = newVal, let n = Int(raw), n > 0 else { return }
                guard n != state.size else { return }
                state.changeSize(n)
                onChange()
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 4) {
                if proxy.size.width < compactWidth {
                    scrollingRow(width: proxy.size.width) {
                        if showsSizeSelector {
                            sizeSelector.fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 12)
                        }
                        infoAndJump.fixedSize(horizontal: true, vertical: false)
                    }
                    scrollingRow(width: proxy.size.width) {
                        Spacer(minLength: 0)
                        navControls.fixedSize(horizontal: true, vertical: false)
                    }
                } else {
                    scrollingRow(width: proxy.size.width) {
                        if showsSizeSelector {
                            sizeSelector.fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 8)
                        }
                        navControls.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        infoAndJump.fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onAppear { updateLayout(width: proxy.size.width) }
            .onChange(of: proxy.size.width) { updateLayout(width: $0) }
        }
        .frame(height: compactLayout ? rowHeight * 2 + 24 : rowHeight + 20)
        .background(AppTheme.cardBg(dark))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.7)),
            alignment: .top
        )
    }

    /// Preserve all controls even for long ranges or unusually small embedded panels.
    private func scrollingRow<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 12, content: content)
                .frame(minWidth: max(0, width - 24), minHeight: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func updateLayout(width: CGFloat) {
        let compact = width < compactWidth
        if compactLayout != compact { compactLayout = compact }
    }

    // MARK: - Size

    private var sizeSelector: some View {
        HStack(spacing: 8) {
            Text("每页")
                .font(.system(size: AppTheme.bodySize))
                .foregroundColor(AppTheme.textSecondary(dark))
            SelectMenu(
                options: sizeOptions,
                selection: sizeSelection,
                placeholder: "\(state.size)",
                width: 78,
                allowClear: false,
                searchable: false
            )
            Text("条")
                .font(.system(size: AppTheme.bodySize))
                .foregroundColor(AppTheme.textSecondary(dark))
        }
    }

    // MARK: - Pages

    private var navControls: some View {
        HStack(spacing: 4) {
            pageButton(systemName: "chevron.left", disabled: state.isFirst) {
                state.goPrev()
                onChange()
            }
            ForEach(visiblePages, id: \.self) { p in
                if p < 0 {
                    Text("…")
                        .font(.system(size: AppTheme.bodySize))
                        .foregroundColor(AppTheme.textSecondary(dark))
                        .frame(width: 22, height: controlHeight)
                } else {
                    Button(action: {
                        state.go(to: p)
                        onChange()
                    }) {
                        Text("\(p + 1)")
                            .font(.system(size: AppTheme.bodySize, weight: p == state.page ? .bold : .regular))
                            .frame(minWidth: controlHeight, minHeight: controlHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(p == state.page ? AppTheme.sidebarActive : AppInputStyle.fill(dark))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        p == state.page ? Color.clear : AppInputStyle.border(dark),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundColor(p == state.page ? .white : AppInputStyle.text(dark))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            pageButton(systemName: "chevron.right", disabled: state.isLast) {
                state.goNext()
                onChange()
            }
        }
    }

    // MARK: - Jump

    private var infoAndJump: some View {
        HStack(spacing: 8) {
            Text(rangeTextOverride ?? state.rangeText)
                .font(.system(size: AppTheme.bodySize))
                .foregroundColor(AppTheme.textSecondary(dark))
                .lineLimit(1)

            if showsJump {
                Text("跳至")
                    .font(.system(size: AppTheme.bodySize))
                    .foregroundColor(AppTheme.textSecondary(dark))

                AppCompactField(
                    text: $jumpText,
                    placeholder: "\(state.displayPage)",
                    width: 56,
                    height: controlHeight,
                    onCommit: { jump() }
                )

                Button(action: jump) {
                    Text("Go")
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(dark))
                        .padding(.horizontal, 12)
                        .frame(height: controlHeight)
                        .background(AppTheme.inputBg(dark))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func pageButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                .frame(width: controlHeight, height: controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppInputStyle.fill(dark))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppInputStyle.border(dark), lineWidth: 1)
                )
                .foregroundColor(AppInputStyle.text(dark))
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }

    private var visiblePages: [Int] {
        let total = state.totalPages
        guard total > 0 else { return [] }
        if total <= 7 { return Array(0..<total) }

        var result: [Int] = []
        let current = state.page
        result.append(0)
        let start = max(1, current - 1)
        let end = min(total - 2, current + 1)
        if start > 1 { result.append(-1) }
        if start <= end {
            result.append(contentsOf: start...end)
        }
        if end < total - 2 { result.append(-2) }
        result.append(total - 1)
        return result
    }

    private func jump() {
        let trimmed = jumpText.trimmingCharacters(in: .whitespaces)
        guard let oneBased = Int(trimmed), oneBased > 0 else { return }
        state.go(to: oneBased - 1)
        jumpText = ""
        onChange()
    }
}
