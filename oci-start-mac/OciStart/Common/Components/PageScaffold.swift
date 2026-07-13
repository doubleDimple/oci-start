import SwiftUI

/// Standard page chrome: title header + optional toolbar + content + optional footer (pagination).
struct PageScaffold<Toolbar: View, Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            footer()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(AppTheme.pageBg(dark))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.sidebarText(dark))
                }
            }
            Spacer()
            toolbar()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.sidebarBg(dark).opacity(0.4))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border(dark).opacity(0.55)),
            alignment: .bottom
        )
    }
}

extension PageScaffold where Toolbar == EmptyView, Footer == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            toolbar: { EmptyView() },
            content: content,
            footer: { EmptyView() }
        )
    }
}

extension PageScaffold where Footer == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil,
         @ViewBuilder toolbar: @escaping () -> Toolbar,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            toolbar: toolbar,
            content: content,
            footer: { EmptyView() }
        )
    }
}
