import SwiftUI

struct TenantListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var tenantToDelete: Tenant?
    @State private var showDeleteAlert = false
    @State private var showAddSheet = false
    @State private var checking = false

    var filtered: [Tenant] {
        guard !searchText.isEmpty else { return appState.tenants }
        let q = searchText.lowercased()
        return appState.tenants.filter {
            ($0.tenancyName?.lowercased().contains(q) ?? false) ||
            ($0.userName?.lowercased().contains(q) ?? false) ||
            ($0.region?.lowercased().contains(q) ?? false) ||
            $0.cloudLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.muted(scheme))
                    .font(.callout)
                TextField("搜索租户名、用户名、区域…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.muted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surface(scheme))
            .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.border(scheme)), alignment: .bottom)

            // Column headers
            HStack(spacing: 0) {
                Text("租户名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("用户名").frame(width: 140, alignment: .leading)
                Text("区域").frame(width: 120, alignment: .leading)
                Text("云平台").frame(width: 70, alignment: .leading)
                Text("状态").frame(width: 60, alignment: .leading)
                Text("操作").frame(width: 100, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppTheme.muted(scheme))
            .background(AppTheme.elevated(scheme))

            Divider().background(AppTheme.border(scheme))

            if appState.tenantsLoading && appState.tenants.isEmpty {
                PageLoadingView(message: "加载租户…")
            } else if filtered.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: appState.tenants.isEmpty ? "暂无租户" : "无匹配结果",
                    subtitle: appState.tenants.isEmpty ? "点击右上角添加 OCI 租户" : nil
                )
            } else {
                List(filtered) { tenant in
                    TenantRowView(tenant: tenant) {
                        tenantToDelete = tenant
                        showDeleteAlert = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("租户管理")
        .toolbar {
            ToolbarItem {
                Text("\(filtered.count) 个租户")
                    .font(.caption)
                    .foregroundColor(AppTheme.muted(scheme))
            }
            ToolbarItem {
                if appState.tenantsLoading || checking { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: {
                    Task {
                        checking = true
                        await appState.checkTenantAccounts()
                        checking = false
                    }
                }) {
                    Label("校验账号", systemImage: "checkmark.shield")
                }
                .disabled(checking || appState.tenants.isEmpty)
                .help("批量检查租户账号状态")
            }
            ToolbarItem {
                Button(action: { Task { await appState.loadTenants() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(appState.tenantsLoading)
            }
            ToolbarItem {
                Button(action: { showAddSheet = true }) {
                    Label("添加租户", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTenantView().environmentObject(appState)
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("确认删除"),
                message: Text("删除租户「\(tenantToDelete?.displayName ?? "")」？此操作不可撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    if let t = tenantToDelete { Task { await appState.deleteTenant(t.id) } }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if appState.tenants.isEmpty { Task { await appState.loadTenants() } }
        }
    }
}

struct TenantRowView: View {
    @Environment(\.colorScheme) private var scheme
    let tenant: Tenant
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tenant.displayName)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.text(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(tenant.userName ?? "—")
                .font(.callout)
                .foregroundColor(AppTheme.muted(scheme))
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Text(tenant.displayRegion)
                .font(.caption)
                .foregroundColor(AppTheme.muted(scheme))
                .frame(width: 120, alignment: .leading)

            Text(tenant.cloudLabel)
                .font(.caption)
                .foregroundColor(AppTheme.accent(scheme))
                .frame(width: 70, alignment: .leading)

            Circle()
                .fill(tenant.enabled == true ? AppTheme.success : Color.gray)
                .frame(width: 8, height: 8)
                .frame(width: 60, alignment: .leading)

            HStack {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(AppTheme.danger)
                }
                .buttonStyle(.plain)
                .help("删除租户")
            }
            .frame(width: 100, alignment: .center)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
    }
}
