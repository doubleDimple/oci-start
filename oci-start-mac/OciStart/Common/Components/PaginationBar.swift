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
    var onChange: () -> Void = {}

    @State private var jumpText: String = ""

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    private let controlHeight: CGFloat = 32

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
        HStack(alignment: .center, spacing: 12) {
            sizeSelector
            Spacer(minLength: 8)
            navControls
            Spacer(minLength: 8)
            infoAndJump
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.sidebarBg(dark).opacity(0.55))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.7)),
            alignment: .top
        )
    }

    // MARK: - Size

    private var sizeSelector: some View {
        HStack(spacing: 8) {
            Text("每页")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
            SelectMenu(
                options: sizeOptions,
                selection: sizeSelection,
                placeholder: "\(state.size)",
                width: 78,
                allowClear: false,
                searchable: false
            )
            Text("条")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
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
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.sidebarText(dark))
                        .frame(width: 22, height: controlHeight)
                } else {
                    Button(action: {
                        state.go(to: p)
                        onChange()
                    }) {
                        Text("\(p + 1)")
                            .font(.system(size: 12, weight: p == state.page ? .bold : .regular))
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
            Text(state.rangeText)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))
                .lineLimit(1)

            Text("跳至")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.sidebarText(dark))

            AppCompactField(
                text: $jumpText,
                placeholder: "\(state.displayPage)",
                width: 56,
                height: controlHeight,
                onCommit: { jump() }
            )

            Button(action: jump) {
                Text("Go")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: controlHeight)
                    .background(AppTheme.sidebarActive)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func pageButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
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
