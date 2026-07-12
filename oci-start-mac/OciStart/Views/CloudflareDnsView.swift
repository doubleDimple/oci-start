import SwiftUI

/// Native Cloudflare DNS (Web: /dns/cloudflare)
struct CloudflareDnsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var zones: [DnsZoneItem] = []
    @State private var records: [DnsRecordItem] = []
    @State private var selectedZone: DnsZoneItem?
    @State private var loadingZones = false
    @State private var loadingRecords = false
    @State private var search = ""
    @State private var showAdd = false
    @State private var editRecord: DnsRecordItem?
    @State private var deleteRecord: DnsRecordItem?
    @State private var showDelete = false

    var filtered: [DnsRecordItem] {
        guard !search.isEmpty else { return records }
        let q = search.lowercased()
        return records.filter {
            $0.name.lowercased().contains(q) ||
            $0.type.lowercased().contains(q) ||
            $0.content.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            zonePanel.frame(minWidth: 180, maxWidth: 260)
            recordPanel
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("Cloudflare")
        .toolbar { toolbar }
        .onAppear { Task { await loadZones() } }
        .sheet(isPresented: $showAdd) {
            if let z = selectedZone {
                DnsEditSheet(
                    title: "添加记录",
                    zoneId: z.id,
                    zoneName: z.name,
                    initial: nil,
                    showProxied: true,
                    onSave: { type, name, content, ttl, proxied in
                        try await appState.network.cfAddRecord(
                            baseURL: appState.serverURL, zoneId: z.id,
                            type: type, name: name, content: content,
                            ttl: ttl, proxied: proxied)
                    },
                    onDone: { showAdd = false; Task { await loadRecords() } }
                )
                .environmentObject(appState)
            }
        }
        .sheet(item: $editRecord) { rec in
            if let z = selectedZone {
                DnsEditSheet(
                    title: "编辑记录",
                    zoneId: z.id,
                    zoneName: z.name,
                    initial: rec,
                    showProxied: true,
                    onSave: { type, name, content, ttl, proxied in
                        try await appState.network.cfUpdateRecord(
                            baseURL: appState.serverURL, recordId: rec.id, zoneId: z.id,
                            type: type, name: name, content: content,
                            ttl: ttl, proxied: proxied)
                    },
                    onDone: { editRecord = nil; Task { await loadRecords() } }
                )
                .environmentObject(appState)
            }
        }
        .alert(isPresented: $showDelete) {
            Alert(
                title: Text("删除 DNS 记录"),
                message: Text(deleteRecord?.name ?? ""),
                primaryButton: .destructive(Text("删除")) {
                    guard let r = deleteRecord, let z = selectedZone else { return }
                    Task {
                        do {
                            let res = try await appState.network.cfDeleteRecord(
                                baseURL: appState.serverURL, recordId: r.id, zoneId: z.id)
                            appState.showToast(res.message ?? "已删除")
                            await loadRecords()
                        } catch { appState.errorMessage = error.localizedDescription }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var zonePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("域名").font(.caption.weight(.semibold)).foregroundColor(AppTheme.muted(scheme))
                Spacer()
            }
            .padding(10)
            .background(AppTheme.elevated(scheme))
            if loadingZones && zones.isEmpty {
                PageLoadingView()
            } else if zones.isEmpty {
                EmptyStateView(icon: "globe", title: "暂无域名",
                               subtitle: "请先在「密钥配置」中配置 Cloudflare")
            } else {
                List(zones) { z in
                    HStack {
                        Image(systemName: "globe").foregroundColor(AppTheme.accent(scheme))
                        Text(z.name).lineLimit(1).foregroundColor(AppTheme.text(scheme))
                    }
                    .tag(z.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedZone = z
                        Task { await loadRecords() }
                    }
                    .listRowBackground(
                        (selectedZone?.id == z.id ? AppTheme.accent(scheme).opacity(0.12) : Color.clear)
                    )
                }
                .listStyle(.sidebar)
            }
        }
        .background(AppTheme.surface(scheme))
    }

    private var recordPanel: some View {
        VStack(spacing: 0) {
            if selectedZone == nil {
                EmptyStateView(icon: "list.bullet", title: "请选择域名")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme))
                    TextField("筛选记录…", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppTheme.elevated(scheme))

                HStack(spacing: 0) {
                    Text("类型").frame(width: 70, alignment: .leading)
                    Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                    Text("内容").frame(maxWidth: .infinity, alignment: .leading)
                    Text("TTL").frame(width: 60, alignment: .leading)
                    Text("代理").frame(width: 50, alignment: .center)
                    Text("操作").frame(width: 90, alignment: .center)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .background(AppTheme.elevated(scheme))

                if loadingRecords {
                    PageLoadingView()
                } else if filtered.isEmpty {
                    EmptyStateView(icon: "doc", title: "暂无记录")
                } else {
                    List(filtered) { r in
                        DnsRecordRowView(
                            record: r,
                            showProxied: true,
                            onEdit: { editRecord = r },
                            onDelete: { deleteRecord = r; showDelete = true }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(AppTheme.pageBg(scheme))
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            if loadingZones || loadingRecords { ProgressView().scaleEffect(0.75) }
        }
        ToolbarItem {
            Button(action: {
                guard selectedZone != nil else { return }
                showAdd = true
            }) {
                Label("添加记录", systemImage: "plus")
            }
            .disabled(selectedZone == nil)
        }
        ToolbarItem {
            Button(action: { Task { await syncZone() } }) {
                Label("同步", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(selectedZone == nil)
        }
        ToolbarItem {
            Button(action: {
                Task {
                    await loadZones()
                    if selectedZone != nil { await loadRecords() }
                }
            }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    private func loadZones() async {
        loadingZones = true
        defer { loadingZones = false }
        do {
            let arr = try await appState.network.cfZones(baseURL: appState.serverURL)
            zones = arr.compactMap { DnsZoneItem(dict: $0) }
            if let cur = selectedZone, !zones.contains(where: { $0.id == cur.id }) {
                selectedZone = nil
                records = []
            }
        } catch {
            appState.errorMessage = error.localizedDescription
            zones = []
        }
    }

    private func loadRecords() async {
        guard let z = selectedZone else { return }
        loadingRecords = true
        defer { loadingRecords = false }
        do {
            let arr = try await appState.network.cfRecords(baseURL: appState.serverURL, zoneId: z.id)
            records = arr.compactMap { DnsRecordItem(dict: $0) }
        } catch {
            appState.errorMessage = error.localizedDescription
            records = []
        }
    }

    private func syncZone() async {
        guard let z = selectedZone else { return }
        do {
            let r = try await appState.network.cfSyncZone(
                baseURL: appState.serverURL, zoneId: z.id, domainName: z.name)
            appState.showToast(r.message ?? "同步完成")
            await loadRecords()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
