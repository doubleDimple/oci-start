import SwiftUI

/// Horizontal filter row: leading filters + trailing actions.
struct FilterBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading()
            Spacer(minLength: 8)
            trailing()
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

/// One list toolbar at normal widths; two compact rows when the window narrows.
/// Horizontal scrolling remains available for unusually long localized labels.
struct AdaptiveListToolbar<Filters: View, Actions: View>: View {
    var compactBelow: CGFloat = 900
    var availableWidth: CGFloat
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            if availableWidth >= compactBelow {
                HStack(spacing: 12) {
                    filters()
                    Spacer(minLength: 8)
                    actions()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { filters() }
                        .frame(minWidth: max(0, availableWidth - 40), alignment: .leading)
                }
                .frame(height: AppInputStyle.height)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { actions() }
                        .frame(minWidth: max(0, availableWidth - 40), alignment: .trailing)
                }
                .frame(height: AppInputStyle.height)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
