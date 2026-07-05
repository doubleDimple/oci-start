import SwiftUI

struct TenantListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var tenantToDelete: Tenant?
    @State private var showDeleteAlert = false
    @State private var showAddSheet = false

    var filtered: [Tenant] {
        guard !searchText.isEmpty else { return appState.tenants }
        let q = searchText.lowercased()
        return appState.tenants.filter {
            ($0.tenancyName?.lowercased().contains(q) ?? false) ||
            ($0.userName?.lowercased().contains(q) ?? false) ||
            ($0.region?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.callout)
                TextField("搜索租户名、用户名、区域…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            // Column headers
            HStack(spacing: 0) {
                Text("租户名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("用户名").frame(width: 140, alignment: .leading)
                Text("区域").frame(width: 120, alignment: .leading)
                Text("云平台").frame(width: 70, alignment: .leading)
                Text("状态").frame(width: 60, alignment: .leading)
                Text("操作").frame(width: 80, alignment: .center)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .font(.caption.weight(.semibold)).foregroundColor(.secondary)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if appState.tenantsLoading && appState.tenants.isEmpty {
                centerView { ProgressView("加载中…") }
            } else if filtered.isEmpty {
                centerView {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2").font(.largeTitle).foregroundColor(.secondary)
                        Text(appState.tenants.isEmpty ? "暂无租户" : "无匹配结果").foregroundColor(.secondary)
                    }
                }
            } else {
                List(filtered) { tenant in
                    TenantRowView(tenant: tenant) {
                        tenantToDelete = tenant
                        showDeleteAlert = true
                    }
                    .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("租户管理")
        .toolbar {
            ToolbarItem {
                Text("\(filtered.count) 个租户").font(.caption).foregroundColor(.secondary)
            }
            ToolbarItem {
                if appState.tenantsLoading { ProgressView().scaleEffect(0.75) }
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

    private func centerView<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack { Spacer(); content(); Spacer() }
    }
}

struct TenantRowView: View {
    let tenant: Tenant
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tenant.displayName).fontWeight(.medium).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(tenant.userName ?? "—")
                .font(.callout).foregroundColor(.secondary).lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Text(tenant.displayRegion)
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(tenant.cloudLabel)
                .font(.caption).foregroundColor(.accentColor)
                .frame(width: 70, alignment: .leading)

            Circle()
                .fill(tenant.enabled == true ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .frame(width: 60, alignment: .leading)

            HStack {
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除租户")
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
