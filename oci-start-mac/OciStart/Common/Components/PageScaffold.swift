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
        .shadow(color: layout == .card ? AppTheme.cardShadow(dark) : .clear,
                radius: AppTheme.cardShadowRadius, y: AppTheme.cardShadowY)
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

/// Vue PageErrorNotice places failures beside the toolbar instead of above the table.
struct PageErrorIndicator: View {
    let message: String
    var retry: (() -> Void)? = nil
    @State private var expanded = false
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var appearance: AppearanceController

    var body: some View {
        Button(action: { expanded.toggle() }) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.danger)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(language.text("查看错误详情", "Show error details"))
        .help(language.text("查看错误详情", "Show error details"))
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(language.text("操作失败", "Operation failed")).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button(action: { expanded = false }) { Image(systemName: "xmark") }
                        .buttonStyle(PlainButtonStyle()).accessibilityLabel(language.text("关闭", "Close"))
                }
                ScrollView { Text(message).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 220)
                if let retry = retry {
                    AppButton(title: language.text("重试", "Retry"), kind: .secondary) { expanded = false; retry() }
                }
            }
            .padding(20).frame(width: 360)
            .foregroundColor(AppTheme.textPrimary(appearance.isDarkEffective))
            .background(AppTheme.cardBg(appearance.isDarkEffective))
        }
        .onChange(of: message) { _ in expanded = false }
    }
}

struct PageToolbarIcon: View {
    let title: String
    let systemImage: String
    var disabled = false
    let action: () -> Void
    @State private var hovered = false
    @EnvironmentObject private var appearance: AppearanceController

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16))
                .foregroundColor(AppTheme.textPrimary(appearance.isDarkEffective))
                .frame(width: 36, height: 36)
                .background(hovered ? AppTheme.hover(appearance.isDarkEffective) : AppTheme.cardBg(appearance.isDarkEffective))
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.borderStrong(appearance.isDarkEffective), lineWidth: 1))
                .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(PlainButtonStyle()).disabled(disabled)
        .onHover { hovered = $0 }.help(title).accessibilityLabel(title)
    }
}
