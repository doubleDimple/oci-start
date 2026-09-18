import SwiftUI

/// List pages share a single card; module grids and immersive tools keep a page surface.
enum PageScaffoldLayout {
    case card, workspace
}

struct PageScaffold<Toolbar: View, Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var layout: PageScaffoldLayout = .card
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            if Toolbar.self != EmptyView.self {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    toolbar()
                }
                .padding(.horizontal, layout == .card ? 20 : AppTheme.pagePadding)
                .padding(.vertical, 12)
            }
            content()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            footer()
        }
        .font(.system(size: AppTheme.bodySize))
        .foregroundColor(AppTheme.textPrimary(dark))
        .accentColor(AppTheme.sidebarActive)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(layout == .card ? AppTheme.cardBg(dark) : AppTheme.pageBg(dark))
        .cornerRadius(layout == .card ? AppTheme.cardRadius : 0)
        .shadow(color: Color.black.opacity(layout == .card && !dark ? 0.04 : 0), radius: 6, y: 2)
        .padding(layout == .card ? AppTheme.pagePadding : 0)
        .background(AppTheme.pageBg(dark))
        .accessibilityIdentifier("page.\(title)")
    }
}

extension PageScaffold where Toolbar == EmptyView, Footer == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, layout: PageScaffoldLayout = .card,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            layout: layout,
            toolbar: { EmptyView() },
            content: content,
            footer: { EmptyView() }
        )
    }
}

extension PageScaffold where Footer == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, layout: PageScaffoldLayout = .card,
         @ViewBuilder toolbar: @escaping () -> Toolbar,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            layout: layout,
            toolbar: toolbar,
            content: content,
            footer: { EmptyView() }
        )
    }
}
