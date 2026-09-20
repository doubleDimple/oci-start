import SwiftUI
import AppKit

/// Keep controls on one line without compressing their labels. Native/AppKit
/// menus remain hosted outside the scroll view by their existing presenters.
struct SingleLineToolbar<Content: View>: View {
    var spacing: CGFloat = 10
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content
    @State private var hasOverflow = false

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .center, spacing: spacing) {
                    content()
                }
                .lineLimit(1)
                .frame(minWidth: max(0, viewport.size.width), minHeight: AppInputStyle.height, alignment: alignment)
                .background(GeometryReader { row in
                    Color.clear.preference(key: ToolbarOverflowPreference.self,
                                           value: row.size.width > viewport.size.width + 1)
                })
            }
        }
        .frame(height: AppInputStyle.height + (hasOverflow ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0))
        .onPreferenceChange(ToolbarOverflowPreference.self) { hasOverflow = $0 }
    }
}

private struct ToolbarOverflowPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Horizontal filter row: leading filters + trailing actions.
struct FilterBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        SingleLineToolbar {
            HStack(spacing: 10) { leading() }
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing() }
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: AppInputStyle.height)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.cardBg(dark).opacity(0.35))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.5)),
            alignment: .bottom
        )
    }
}

extension FilterBar where Trailing == EmptyView {
    init(@ViewBuilder leading: @escaping () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}

/// Filters and actions share one row at every width, with horizontal overflow.
struct AdaptiveListToolbar<Filters: View, Actions: View>: View {
    // Retained for existing call sites; narrow windows now scroll instead of wrapping.
    var compactBelow: CGFloat = 900
    var availableWidth: CGFloat
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        SingleLineToolbar(spacing: 12) {
            HStack(spacing: 10) { filters() }
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(spacing: 8) { actions() }
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
