import SwiftUI

/// Temporary page until feature is natively implemented.
/// Also demos Common components for packaging QA.
struct PlaceholderView: View {
    let nav: NavID
    let title: String
    let webPath: String

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme

    @State private var demoSearch = ""
    @State private var demoSelect: String? = nil
    @State private var demoPage = PageState(page: 0, size: 20, totalElements: 128, totalPages: 7)

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    private let demoOptions: [SelectOption] = [
        SelectOption(id: "all", title: "全部"),
        SelectOption(id: "running", title: "运行中"),
        SelectOption(id: "stopped", title: "已停止")
    ]

    var body: some View {
        PageScaffold(
            title: title,
            subtitle: webPath.isEmpty ? "待原生化" : "Web: \(webPath)",
            systemImage: NavigationCatalog.item(for: nav)?.systemImage,
            toolbar: {
                HStack(spacing: 8) {
                    AppButton(title: "Loading 示例", kind: .secondary) {
                        Task {
                            await LoadingHUD.shared.during {
                                try? await Task.sleep(nanoseconds: 800_000_000)
                            }
                        }
                    }
                    AppButton(title: "刷新", systemImage: "arrow.clockwise", kind: .primary) {
                        NotificationCenter.default.post(name: .ociReloadCurrentPage, object: nil)
                    }
                }
            },
            content: {
                VStack(spacing: 0) {
                    FilterBar(
                        leading: {
                            HStack(spacing: 10) {
                                SearchField(text: $demoSearch, placeholder: "搜索（公共组件）")
                                SelectMenu(
                                    options: demoOptions,
                                    selection: $demoSelect,
                                    placeholder: "状态下拉",
                                    width: 140
                                )
                                StatusBadge.state("RUNNING")
                                StatusBadge(text: "STOPPED", tone: .danger)
                            }
                        },
                        trailing: {
                            AppButton(title: "查询", systemImage: "magnifyingglass", kind: .primary) {
                                Task {
                                    await LoadingHUD.shared.during {
                                        try? await Task.sleep(nanoseconds: 400_000_000)
                                    }
                                }
                            }
                        }
                    )

                    SectionCard(title: "页面说明") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("此页尚未原生化，当前为占位 + Common 组件预览。")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.sidebarText(dark))
                            KeyValueRow(key: "NavID", value: nav.rawValue)
                            KeyValueRow(key: "Web Path", value: webPath.isEmpty ? "—" : webPath)
                            KeyValueRow(key: "实现顺序", value: "按 Web 侧栏自上而下逐个替换本占位")
                        }
                    }
                    .padding(16)

                    DataList(
                        header: {
                            DataListColumnHeader(title: "示例列 A", width: 160)
                            DataListColumnHeader(title: "示例列 B")
                            DataListColumnHeader(title: "状态", width: 100)
                        },
                        content: {
                            ForEach(0..<5, id: \.self) { i in
                                DataListRow {
                                    Text("Row \(i + 1)")
                                        .font(.system(size: 12))
                                        .frame(width: 160, alignment: .leading)
                                    Text("公共列表行样式")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.sidebarText(dark))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    StatusBadge(text: i % 2 == 0 ? "ACTIVE" : "IDLE",
                                                tone: i % 2 == 0 ? .success : .neutral)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                        }
                    )
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    EmptyStateView(
                        icon: "hammer",
                        title: "业务 UI 待实现",
                        subtitle: "下拉 / 分页 / 列表 / Loading 已走 Common，业务页请直接复用"
                    )
                    .frame(maxHeight: 160)
                }
            },
            footer: {
                PaginationBar(state: $demoPage) {
                    Task {
                        await LoadingHUD.shared.during {
                            try? await Task.sleep(nanoseconds: 250_000_000)
                        }
                    }
                }
            }
        )
    }
}
