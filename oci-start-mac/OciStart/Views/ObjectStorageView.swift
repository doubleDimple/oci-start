import SwiftUI
import AppKit

struct ObjectStorageView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var selectedTenant: Tenant?
    @State private var selectedBucket: StorageBucket?
    @State private var objectToDelete: StorageObject?
    @State private var showDeleteAlert = false
    @State private var showCreateBucket = false
    @State private var newBucketName = ""
    @State private var prefixFilter = ""

    var body: some View {
        HSplitView {
            bucketPanel.frame(minWidth: 200, maxWidth: 280)
            objectPanel
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("对象存储")
        .toolbar { toolbarItems }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("确认删除"),
                message: Text("删除文件「\(objectToDelete?.name ?? "")」？"),
                primaryButton: .destructive(Text("删除")) { deleteSelectedObject() },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showCreateBucket) {
            createBucketSheet
        }
        .onAppear {
            if appState.allTenants.isEmpty { Task { await appState.loadAllTenants() } }
        }
    }

    private var bucketPanel: some View {
        VStack(spacing: 0) {
            Picker("租户", selection: $selectedTenant) {
                Text("选择租户…").tag(Optional<Tenant>.none)
                ForEach(appState.allTenants) { t in
                    Text(t.displayName).tag(Optional(t))
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .onChange(of: selectedTenant) { t in
                selectedBucket = nil
                appState.buckets = []
                appState.storageObjects = []
                if let t = t { Task { await appState.loadBuckets(tenantId: t.id) } }
            }

            Divider()

            if appState.storageLoading && appState.buckets.isEmpty {
                PageLoadingView()
            } else if appState.buckets.isEmpty {
                EmptyStateView(
                    icon: "externaldrive",
                    title: selectedTenant == nil ? "请选择租户" : "暂无 Bucket",
                    subtitle: selectedTenant == nil ? nil : "可点击工具栏创建存储桶"
                )
            } else {
                List(appState.buckets, selection: $selectedBucket) { bucket in
                    HStack {
                        Image(systemName: "externaldrive").foregroundColor(AppTheme.accent(scheme))
                        Text(bucket.name).lineLimit(1).foregroundColor(AppTheme.text(scheme))
                    }
                    .tag(bucket)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedBucket) { bucket in
                    guard let t = selectedTenant, let b = bucket, let ns = b.namespace else { return }
                    Task { await appState.loadObjects(tenantId: t.id, namespace: ns, bucketName: b.name) }
                }
            }
        }
        .background(AppTheme.surface(scheme))
    }

    private var objectPanel: some View {
        VStack(spacing: 0) {
            if selectedBucket == nil {
                EmptyStateView(icon: "folder", title: "请选择 Bucket")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(AppTheme.muted(scheme))
                    TextField("前缀筛选", text: $prefixFilter)
                        .textFieldStyle(.plain)
                    Button("筛选") { reloadObjects() }
                        .buttonStyle(.plain)
                        .foregroundColor(AppTheme.accent(scheme))
                    if !prefixFilter.isEmpty {
                        Button("清除") { prefixFilter = ""; reloadObjects() }
                            .buttonStyle(.plain)
                            .foregroundColor(AppTheme.accent(scheme))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppTheme.elevated(scheme))

                HStack(spacing: 0) {
                    Text("文件名").frame(maxWidth: .infinity, alignment: .leading)
                    Text("大小").frame(width: 100, alignment: .trailing)
                    Text("修改时间").frame(width: 160, alignment: .leading)
                    Text("操作").frame(width: 100, alignment: .center)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.muted(scheme))
                .background(AppTheme.elevated(scheme))

                Divider()

                if appState.storageLoading {
                    PageLoadingView()
                } else if appState.storageObjects.isEmpty {
                    EmptyStateView(icon: "doc", title: "Bucket 为空", subtitle: "可点击工具栏上传文件")
                } else {
                    List(appState.storageObjects) { obj in
                        ObjectRowView(
                            object: obj,
                            onDownload: { downloadObject(obj) },
                            onDelete: { objectToDelete = obj; showDeleteAlert = true }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(AppTheme.pageBg(scheme))
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var createBucketSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("创建存储桶").font(.headline)
            TextField("bucket-name", text: $newBucketName)
                .textFieldStyle(.roundedBorder)
            Text("名称需全局唯一，建议小写字母与连字符。")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
            HStack {
                Spacer()
                Button("取消") { showCreateBucket = false }
                Button("创建") {
                    guard let t = selectedTenant else { return }
                    let name = newBucketName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task {
                        await appState.createBucket(tenantId: t.id, name: name)
                        showCreateBucket = false
                        newBucketName = ""
                    }
                }
                .buttonStyle(ProminentButton())
                .disabled(selectedTenant == nil || newBucketName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            if appState.storageLoading { ProgressView().scaleEffect(0.75) }
        }
        ToolbarItem {
            Button(action: { showCreateBucket = true }) {
                Label("创建桶", systemImage: "plus.rectangle.on.folder")
            }
            .disabled(selectedTenant == nil)
        }
        ToolbarItem {
            Button(action: pickAndUpload) {
                Label("上传", systemImage: "arrow.up.doc")
            }
            .disabled(selectedTenant == nil || selectedBucket == nil)
        }
        ToolbarItem {
            Button(action: refresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(selectedTenant == nil)
        }
    }

    private func refresh() {
        guard let t = selectedTenant else { return }
        Task {
            await appState.loadBuckets(tenantId: t.id)
            reloadObjects()
        }
    }

    private func reloadObjects() {
        guard let t = selectedTenant, let b = selectedBucket, let ns = b.namespace else { return }
        Task {
            await appState.loadObjects(tenantId: t.id, namespace: ns, bucketName: b.name)
            // client-side prefix filter (API also supports prefix; keep simple for 11.7)
            if !prefixFilter.isEmpty {
                let p = prefixFilter
                appState.storageObjects = appState.storageObjects.filter { $0.name.hasPrefix(p) }
            }
        }
    }

    private func pickAndUpload() {
        guard let t = selectedTenant, let b = selectedBucket, let ns = b.namespace else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            Task {
                await appState.uploadObject(tenantId: t.id, namespace: ns, bucketName: b.name, fileURL: url)
            }
        }
    }

    private func downloadObject(_ obj: StorageObject) {
        guard let t = selectedTenant, let b = selectedBucket, let ns = b.namespace else { return }
        guard let url = appState.network.downloadURLForObject(
            baseURL: appState.serverURL, tenantId: t.id, namespace: ns,
            bucketName: b.name, objectName: obj.name
        ) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: obj.name).lastPathComponent
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            Task {
                do {
                    let (data, _) = try await URLSession.shared.compatData(from: url)
                    try data.write(to: dest)
                    appState.showToast("已下载到 \(dest.lastPathComponent)")
                } catch {
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteSelectedObject() {
        guard let t = selectedTenant, let b = selectedBucket,
              let ns = b.namespace, let obj = objectToDelete else { return }
        Task {
            await appState.deleteObject(tenantId: t.id, namespace: ns, bucketName: b.name, objectName: obj.name)
            if let idx = appState.storageObjects.firstIndex(where: { $0.name == obj.name }) {
                appState.storageObjects.remove(at: idx)
            }
        }
    }
}

struct ObjectRowView: View {
    @Environment(\.colorScheme) private var scheme
    let object: StorageObject
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc").foregroundColor(AppTheme.muted(scheme)).font(.callout)
                Text(object.name).lineLimit(1).foregroundColor(AppTheme.text(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(object.sizeDisplay)
                .font(.callout).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 100, alignment: .trailing)

            Text(object.timeModified.map { String($0.prefix(10)) } ?? "—")
                .font(.caption).foregroundColor(AppTheme.muted(scheme))
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle").foregroundColor(AppTheme.accent(scheme))
                }.buttonStyle(.plain).help("下载")
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(AppTheme.danger)
                }.buttonStyle(.plain).help("删除")
            }
            .frame(width: 100, alignment: .center)
        }
        .padding(.vertical, 7).padding(.horizontal, 16)
    }
}
