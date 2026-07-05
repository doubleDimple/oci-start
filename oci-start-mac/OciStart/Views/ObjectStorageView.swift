import SwiftUI
import AppKit

struct ObjectStorageView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedTenant: Tenant?
    @State private var selectedBucket: StorageBucket?
    @State private var objectToDelete: StorageObject?
    @State private var showDeleteAlert = false

    var body: some View {
        HSplitView {
            // Left: bucket list
            bucketPanel
                .frame(minWidth: 200, maxWidth: 260)

            // Right: object list
            objectPanel
        }
        .navigationTitle("对象存储")
        .toolbar { toolbarItems }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("确认删除"),
                message: Text("删除文件「\(objectToDelete?.name ?? "")」？"),
                primaryButton: .destructive(Text("删除")) {
                    deleteSelectedObject()
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if appState.allTenants.isEmpty { Task { await appState.loadAllTenants() } }
        }
    }

    // MARK: - Bucket Panel

    private var bucketPanel: some View {
        VStack(spacing: 0) {
            // Tenant picker
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
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if appState.buckets.isEmpty {
                VStack {
                    Spacer()
                    Text(selectedTenant == nil ? "请选择租户" : "暂无 Bucket")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(appState.buckets, selection: $selectedBucket) { bucket in
                    HStack {
                        Image(systemName: "externaldrive").foregroundColor(.accentColor)
                        Text(bucket.name).lineLimit(1)
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
    }

    // MARK: - Object Panel

    private var objectPanel: some View {
        VStack(spacing: 0) {
            if selectedBucket == nil {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.largeTitle).foregroundColor(.secondary)
                        Text("请选择 Bucket").foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("文件名").frame(maxWidth: .infinity, alignment: .leading)
                    Text("大小").frame(width: 100, alignment: .trailing)
                    Text("修改时间").frame(width: 160, alignment: .leading)
                    Text("操作").frame(width: 100, alignment: .center)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if appState.storageLoading {
                    VStack { Spacer(); ProgressView("加载中…"); Spacer() }
                } else if appState.storageObjects.isEmpty {
                    VStack { Spacer(); Text("Bucket 为空").foregroundColor(.secondary); Spacer() }
                } else {
                    List(appState.storageObjects) { obj in
                        ObjectRowView(object: obj,
                            onDownload: { downloadObject(obj) },
                            onDelete: { objectToDelete = obj; showDeleteAlert = true }
                        )
                        .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            if appState.storageLoading { ProgressView().scaleEffect(0.75) }
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
            if let b = selectedBucket, let ns = b.namespace {
                await appState.loadObjects(tenantId: t.id, namespace: ns, bucketName: b.name)
            }
        }
    }

    private func downloadObject(_ obj: StorageObject) {
        guard let t = selectedTenant, let b = selectedBucket, let ns = b.namespace else { return }
        guard let url = appState.network.downloadURLForObject(
            baseURL: appState.serverURL,
            tenantId: t.id,
            namespace: ns,
            bucketName: b.name,
            objectName: obj.name
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
    let object: StorageObject
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: fileIcon).foregroundColor(.secondary).font(.callout)
                Text(object.name).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(object.sizeDisplay)
                .font(.callout).foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(object.timeModified.map { String($0.prefix(10)) } ?? "—")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 160, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
                }.buttonStyle(.plain).help("下载")

                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }.buttonStyle(.plain).help("删除")
            }
            .frame(width: 100, alignment: .center)
        }
        .padding(.vertical, 7).padding(.horizontal, 16)
    }

    private var fileIcon: String {
        let ext = (object.name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg","jpeg","png","gif","webp","svg": return "photo"
        case "mp4","avi","mov","mkv":               return "film"
        case "mp3","wav","aac","flac":              return "music.note"
        case "zip","tar","gz","7z","rar":           return "archivebox"
        case "pdf":                                 return "doc.richtext"
        case "txt","md","log":                      return "doc.text"
        case "sh","py","js","java","swift":         return "doc.badge.gearshape"
        default:                                    return "doc"
        }
    }
}
