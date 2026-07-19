import SwiftUI

/// 尚未交付完整业务逻辑的菜单占位（原生，禁止 WebEmbed）。
struct PlaceholderView: View {
    let nav: NavID
    let title: String
    let webPath: String

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        PageScaffold(
            title: title,
            subtitle: "原生占位 · 业务功能开发中",
            systemImage: NavigationCatalog.item(for: nav)?.systemImage ?? "hammer",
            toolbar: {
                AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .secondary) {
                    NotificationCenter.default.post(name: .ociReloadCurrentPage, object: nil)
                }
            },
            content: {
                VStack(spacing: 16) {
                    Spacer(minLength: 24)
                    EmptyStateView(
                        icon: NavigationCatalog.item(for: nav)?.systemImage ?? "hammer",
                        title: "\(title) 待完整实现",
                        subtitle: "当前为原生占位页，不嵌入 Web 页面。Web 参考路径：\(webPath.isEmpty ? "—" : webPath)"
                    )
                    .frame(maxWidth: 520)

                    VStack(alignment: .leading, spacing: 8) {
                        KeyValueRow(key: "NavID", value: nav.rawValue)
                        KeyValueRow(key: "菜单分组", value: NavigationCatalog.section(for: nav)?.title ?? "—")
                        KeyValueRow(key: "Web Path", value: webPath.isEmpty ? "—" : webPath)
                    }
                    .padding(16)
                    .frame(maxWidth: 520)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.sidebarBg(dark))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border(dark).opacity(0.55), lineWidth: 1)
                    )

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
