import SwiftUI

/// Lightweight list shell for Big Sur (header + rows). Prefer over macOS-12-only Table.
struct DataList<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.sidebarHover(dark).opacity(0.65))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(AppTheme.border(dark).opacity(0.5)),
                alignment: .bottom
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    content()
                }
            }
        }
    }
}

struct DataListRow<Content: View>: View {
    var isSelected: Bool = false
    let action: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    init(isSelected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AppTheme.sidebarActive.opacity(0.18)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.35)),
            alignment: .bottom
        )
    }
}

struct DataListColumnHeader: View {
    let title: String
    var width: CGFloat? = nil
    var alignment: Alignment = .leading

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.sidebarText(dark))
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}
