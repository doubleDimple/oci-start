import SwiftUI

/// Native counterpart of the Vue console's full-height navigation rail.
struct SidebarView: View {
    @EnvironmentObject private var navigation: NavigationState
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @ObservedObject private var backend = BackendController.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredItem: NavID?

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }
    private var collapsed: Bool { navigation.sidebarCollapsed }

    var body: some View {
        VStack(spacing: 0) {
            brand

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let catalog = NavigationCatalog.filtered(
                        search: navigation.searchText,
                        cloudType: session.cloudProvider
                    )
                    if catalog.isEmpty {
                        Text("无匹配菜单")
                            .font(.system(size: AppTheme.secondarySize))
                            .foregroundColor(AppTheme.sidebarText(dark))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        ForEach(catalog, id: \.0) { section, items in
                            if !collapsed {
                                sectionHeader(section)
                            } else {
                                Color.clear.frame(height: 8)
                            }
                            // The compact rail keeps every destination accessible.
                            if collapsed || navigation.isSectionExpanded(section)
                                || !navigation.searchText.isEmpty {
                                ForEach(items) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, collapsed ? 16 : 12)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebarBg(dark))
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Button(action: { navigation.sidebarCollapsed.toggle() }) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.brand(dark)))
            }
            .buttonStyle(PlainButtonStyle())
            .help(collapsed ? "展开侧栏（⌘⌥S）" : "收起侧栏（⌘⌥S）")
            .accessibilityLabel(collapsed ? "展开侧栏" : "收起侧栏")

            if !collapsed {
                Button(action: { navigation.select(.dashboard) }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.siteName)
                            .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("云资源控制台")
                            .font(.system(size: AppTheme.captionSize))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("回到系统监控")
            }
        }
        .padding(.horizontal, collapsed ? 20 : 18)
        .frame(height: 84)
    }

    private func sectionHeader(_ section: NavSection) -> some View {
        Button(action: { navigation.toggleSection(section) }) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.system(size: AppTheme.captionSize, weight: .medium))
                Spacer(minLength: 4)
                Image(systemName: navigation.isSectionExpanded(section) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(AppTheme.sidebarText(dark).opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func row(_ item: NavigationItem) -> some View {
        let selected = navigation.selected == item.nav
        return Button(action: { navigation.select(item.nav) }) {
            HStack(spacing: 11) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .frame(width: 20)
                if !collapsed {
                    Text(item.title)
                        .font(.system(size: AppTheme.bodySize, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? AppTheme.sidebarActive : (hoveredItem == item.nav ? AppTheme.sidebarHover(dark) : .clear))
            )
            .foregroundColor(selected ? .white : AppTheme.sidebarText(dark))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(item.title)
        .accessibilityLabel(item.title)
        .onHover { hovering in hoveredItem = hovering ? item.nav : nil }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)

            HStack(spacing: 8) {
                Image(systemName: session.isRemoteDeployment ? "network" : "desktopcomputer")
                    .font(.system(size: AppTheme.secondarySize))
                    .frame(width: 20)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(serviceTitle)
                            .font(.system(size: AppTheme.captionSize, weight: .medium))
                        Text(serverHost)
                            .font(.system(size: AppTheme.captionSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
            }
            .foregroundColor(AppTheme.sidebarText(dark))
            .help("\(serviceTitle) · \(session.serverURL)")

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(AppTheme.brand(dark).opacity(0.32))
                    Text(String(session.username.first ?? "A").uppercased())
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.username.isEmpty ? "Admin" : session.username)
                            .font(.system(size: AppTheme.bodySize, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(session.cloudProviderName)
                            .font(.system(size: AppTheme.captionSize))
                            .foregroundColor(AppTheme.sidebarText(dark))
                    }
                    Spacer(minLength: 0)
                }
            }
            .help(session.username.isEmpty ? "Admin" : session.username)
        }
        .padding(.horizontal, collapsed ? 21 : 20)
        .padding(.bottom, 20)
    }

    private var serverHost: String {
        URL(string: session.serverURL)?.host ?? session.serverURL
    }

    private var serviceTitle: String {
        if session.isRemoteDeployment { return "远程服务器" }
        switch backend.state {
        case .idle: return "本机服务"
        case .starting: return "本机服务启动中"
        case .ready: return "本机服务已就绪"
        case .failed: return "本机服务异常"
        }
    }
}
