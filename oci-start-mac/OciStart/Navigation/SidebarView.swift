import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var navigation: NavigationState
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let catalog = NavigationCatalog.filtered(
                        search: navigation.searchText,
                        cloudType: session.cloudProvider
                    )
                    if catalog.isEmpty {
                        Text("无匹配菜单")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.sidebarText(dark).opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        ForEach(catalog, id: \.0) { section, items in
                            sectionHeader(section)
                            // Accordion: only the expanded first-level section shows children
                            // (search mode expands all matches)
                            if navigation.isSectionExpanded(section)
                                || !navigation.searchText.isEmpty {
                                ForEach(items) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }

            Divider().background(AppTheme.border(dark))
            collapseButton
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebarBg(dark))
    }

    private var searchBar: some View {
        SearchField(
            text: $navigation.searchText,
            placeholder: "搜索菜单…",
            fillsWidth: true
        )
    }

    private func sectionHeader(_ section: NavSection) -> some View {
        Button(action: { navigation.toggleSection(section) }) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(section.title)
                    // 一级菜单应大于二级项（web sidebar parent ~13–14px bold）
                    .font(.system(size: 13.5, weight: .bold))
                Spacer(minLength: 4)
                Image(systemName: navigation.isSectionExpanded(section) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.75)
            }
            .foregroundColor(dark ? Color.white.opacity(0.88) : AppTheme.sidebarText(dark))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 10)
    }

    private func row(_ item: NavigationItem) -> some View {
        let selected = navigation.selected == item.nav
        return Button(action: { navigation.select(item.nav) }) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(item.title)
                    // 二级菜单略小于一级
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? AppTheme.sidebarActive.opacity(0.9) : Color.clear)
            )
            .foregroundColor(selected ? Color.white : AppTheme.sidebarText(dark))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 6)
        .onHover { hovering in
            _ = hovering
        }
    }

    private var collapseButton: some View {
        Button(action: { navigation.sidebarCollapsed.toggle() }) {
            HStack {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                Text(navigation.sidebarCollapsed ? "展开侧栏" : "收起侧栏")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(AppTheme.sidebarText(dark).opacity(0.75))
            .padding(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
