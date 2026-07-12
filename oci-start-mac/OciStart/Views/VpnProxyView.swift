import SwiftUI

/// Native VPN / HTTP proxy list (Web: /vpnProxy/page)
struct VpnProxyView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var items: [VpnProxyRecord] = []
    @State private var loading = false
    @State private var search = ""
    @State private var showEditor = false
    @State private var editing: VpnProxyEditState = .empty
    @State private var deleteItem: VpnProxyRecord?
    @State private var showDelete = false
    @State private var showPasswordIds: Set<Int64> = []

    var filtered: [VpnProxyRecord] {
        guard !search.isEmpty else { return items }
        let q = search.lowercased()
        return items.filter {
            $0.proxyHost.lowercased().contains(q)
                || $0.proxyType.lowercased().contains(q)
                || $0.proxyUsername.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme))
                TextField("搜索主机 / 类型 / 用户…", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(AppTheme.elevated(scheme))

            HStack(spacing: 0) {
                Text("类型").frame(width: 72, alignment: .leading)
                Text("主机").frame(maxWidth: .infinity, alignment: .leading)
                Text("端口").frame(width: 64, alignment: .leading)
                Text("用户").frame(width: 100, alignment: .leading)
                Text("密码").frame(width: 100, alignment: .leading)
                Text("状态").frame(width: 72, alignment: .center)
                Text("操作").frame(width: 90, alignment: .center)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppTheme.muted(scheme))
            .background(AppTheme.elevated(scheme))

            Divider()

            if loading && items.isEmpty {
                PageLoadingView()
            } else if filtered.isEmpty {
                EmptyStateView(icon: "arrow.triangle.branch", title: "暂无代理",
                               subtitle: "点击右上角添加 HTTP/HTTPS 代理")
            } else {
                List(filtered) { item in
                    HStack(spacing: 0) {
                        Text(item.proxyType)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.text(scheme))
                            .frame(width: 72, alignment: .leading)
                        Text(item.proxyHost)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(AppTheme.text(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text("\(item.proxyPort)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(AppTheme.muted(scheme))
                            .frame(width: 64, alignment: .leading)
                        Text(item.proxyUsername.isEmpty ? "—" : item.proxyUsername)
                            .foregroundColor(AppTheme.muted(scheme))
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)
                        passwordCell(item)
                            .frame(width: 100, alignment: .leading)
                        statusBadge(item.isEnabled)
                            .frame(width: 72, alignment: .center)
                        HStack(spacing: 10) {
                            Button(action: { openEdit(item) }) {
                                Image(systemName: "pencil").foregroundColor(AppTheme.accent(scheme))
                            }
                            .buttonStyle(.plain)
                            Button(action: { deleteItem = item; showDelete = true }) {
                                Image(systemName: "trash").foregroundColor(AppTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 90, alignment: .center)
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(AppTheme.pageBg(scheme))
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("代理配置")
        .toolbar {
            ToolbarItem {
                if loading { ProgressView().scaleEffect(0.75) }
            }
            ToolbarItem {
                Button(action: { openAdd() }) {
                    Label("添加代理", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button(action: { Task { await load() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { Task { await load() } }
        .sheet(isPresented: $showEditor) {
            VpnProxyEditorSheet(state: $editing) {
                Task { await save() }
            }
            .environmentObject(appState)
        }
        .alert(isPresented: $showDelete) {
            Alert(
                title: Text("删除代理"),
                message: Text(deleteItem.map { "\($0.proxyType) \($0.proxyHost):\($0.proxyPort)" } ?? ""),
                primaryButton: .destructive(Text("删除")) {
                    guard let item = deleteItem else { return }
                    Task { await delete(item) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func passwordCell(_ item: VpnProxyRecord) -> some View {
        if item.proxyPassword.isEmpty {
            Text("—").foregroundColor(AppTheme.muted(scheme))
        } else {
            Button(action: {
                if showPasswordIds.contains(item.id) {
                    showPasswordIds.remove(item.id)
                } else {
                    showPasswordIds.insert(item.id)
                }
            }) {
                Text(showPasswordIds.contains(item.id) ? item.proxyPassword : "••••••••")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppTheme.muted(scheme))
            }
            .buttonStyle(.plain)
        }
    }

    private func statusBadge(_ on: Bool) -> some View {
        Text(on ? "可用" : "停用")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((on ? Color.green : Color.gray).opacity(0.18))
            .foregroundColor(on ? .green : .secondary)
            .cornerRadius(6)
    }

    private func openAdd() {
        editing = .empty
        showEditor = true
    }

    private func openEdit(_ item: VpnProxyRecord) {
        editing = VpnProxyEditState(
            id: item.id,
            proxyType: item.proxyType,
            proxyHost: item.proxyHost,
            proxyPort: "\(item.proxyPort)",
            proxyUsername: item.proxyUsername,
            proxyPassword: item.proxyPassword,
            availableStatus: item.availableStatus
        )
        showEditor = true
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let arr = try await appState.network.vpnProxyList(baseURL: appState.serverURL)
            items = arr.compactMap { VpnProxyRecord(dict: $0) }
        } catch {
            appState.errorMessage = error.localizedDescription
            items = []
        }
    }

    private func save() async {
        let port = Int(editing.proxyPort) ?? 0
        guard !editing.proxyHost.isEmpty, (1...65535).contains(port) else {
            appState.errorMessage = "请填写主机，端口范围 1–65535"
            return
        }
        do {
            let r = try await appState.network.vpnProxySave(
                baseURL: appState.serverURL,
                id: editing.id,
                proxyType: editing.proxyType,
                proxyHost: editing.proxyHost.trimmingCharacters(in: .whitespaces),
                proxyPort: port,
                proxyUsername: editing.proxyUsername.isEmpty ? nil : editing.proxyUsername,
                proxyPassword: editing.proxyPassword.isEmpty ? nil : editing.proxyPassword,
                availableStatus: editing.availableStatus)
            if r.success == false {
                appState.errorMessage = r.message ?? "保存失败"
                return
            }
            appState.showToast(r.message ?? "已保存")
            showEditor = false
            await load()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: VpnProxyRecord) async {
        do {
            let r = try await appState.network.vpnProxyDelete(baseURL: appState.serverURL, id: item.id)
            if r.success == false {
                appState.errorMessage = r.message ?? "删除失败"
                return
            }
            appState.showToast(r.message ?? "已删除")
            await load()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Editor

struct VpnProxyEditState {
    var id: Int64?
    var proxyType: String
    var proxyHost: String
    var proxyPort: String
    var proxyUsername: String
    var proxyPassword: String
    var availableStatus: Int
    var saving = false

    static var empty: VpnProxyEditState {
        VpnProxyEditState(id: nil, proxyType: "HTTP", proxyHost: "", proxyPort: "8080",
                          proxyUsername: "", proxyPassword: "", availableStatus: 1)
    }
}

struct VpnProxyEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @Binding var state: VpnProxyEditState
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.id == nil ? "添加代理" : "编辑代理")
                .font(.headline)

            Picker("类型", selection: $state.proxyType) {
                Text("HTTP").tag("HTTP")
                Text("HTTPS").tag("HTTPS")
            }
            .pickerStyle(.segmented)

            TextField("主机（IP / 域名）", text: $state.proxyHost)
                .textFieldStyle(.roundedBorder)
            TextField("端口", text: $state.proxyPort)
                .textFieldStyle(.roundedBorder)
            TextField("用户名（可选）", text: $state.proxyUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("密码（可选）", text: $state.proxyPassword)
                .textFieldStyle(.roundedBorder)

            Picker("状态", selection: $state.availableStatus) {
                Text("可用").tag(1)
                Text("停用").tag(0)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                Button("保存") { onSave() }
                    .buttonStyle(ProminentButton())
                    .disabled(state.proxyHost.isEmpty || state.proxyPort.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}
