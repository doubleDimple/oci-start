import Foundation
import Combine
import AppKit

/// ViewModel for Web `/oci/storage/page` — buckets + objects + upload/download.
@MainActor
final class StorageViewModel: ObservableObject {

    // MARK: - Tenant

    @Published var parentTenants: [TenantRegionOption] = []
    @Published var selectedTenantId: String = ""
    @Published private(set) var namespace: String = ""

    // MARK: - Buckets

    @Published private(set) var buckets: [StorageBucketItem] = []
    @Published var bucketSearch = ""
    @Published private(set) var bucketNextToken: String?
    @Published private(set) var bucketsLoading = false
    @Published private(set) var selectedBucket: StorageBucketItem?

    // MARK: - Objects (cursor pages)

    @Published private(set) var objects: [StorageObjectItem] = []
    @Published private(set) var objectsLoading = false
    /// Token stack for prev/next (index 0 = first page, token=nil).
    private var objectTokens: [String?] = [nil]
    @Published private(set) var objectPageIndex: Int = 0
    @Published private(set) var objectHasNext = false
    private let objectPageLimit = 20

    // MARK: - UI state

    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published var activeSheet: StorageSheet?

    // Create bucket form
    @Published var newBucketName = ""
    @Published var newBucketAccess: StorageAccessType = .noPublic
    @Published var formBusy = false
    @Published var formError: String?

    // Presigned
    @Published var presignedURLText = ""

    // Upload
    @Published var uploadTasks: [StorageUploadTask] = []
    @Published var uploadOverallPercent: Int = 0
    @Published var uploadFinished = false
    private var uploadCancelled = false
    private var activeUploadId: String?

    private let session: AppSession
    private var service: StorageService { StorageService(baseURL: session.serverURL) }

    var tenantIdValue: Int64? {
        Int64(selectedTenantId)
    }

    var filteredBuckets: [StorageBucketItem] {
        let kw = bucketSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if kw.isEmpty { return buckets }
        return buckets.filter { $0.name.lowercased().contains(kw) }
    }

    var hasMoreBuckets: Bool { bucketNextToken != nil && !bucketNextToken!.isEmpty }

    var objectPageLabel: String {
        "第 \(objectPageIndex + 1) 页"
    }

    init(session: AppSession = .shared) {
        self.session = session
    }

    // MARK: - Lifecycle

    func start() {
        Task { await loadTenants() }
    }

    func reloadAll() async {
        await loadTenants()
        if !selectedTenantId.isEmpty {
            await loadBuckets(reset: true)
            if selectedBucket != nil {
                await loadObjects(reset: true)
            }
        }
    }

    // MARK: - Tenants

    func loadTenants() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            var list = try await service.listParentTenants()
            list.sort {
                let a = $0.userName.isEmpty ? $0.tenancyName : $0.userName
                let b = $1.userName.isEmpty ? $1.tenancyName : $1.userName
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            parentTenants = list
        } catch {
            parentTenants = []
            handleError(error)
        }
    }

    func onTenantChanged(_ id: String?) {
        selectedTenantId = id ?? ""
        namespace = ""
        buckets = []
        bucketNextToken = nil
        bucketSearch = ""
        clearObjectPanel()
        guard !selectedTenantId.isEmpty else { return }
        Task { await loadBuckets(reset: true) }
    }

    func tenantLabel(_ t: TenantRegionOption) -> String {
        if !t.userName.isEmpty { return t.userName }
        if !t.tenancyName.isEmpty { return t.tenancyName }
        return t.id
    }

    // MARK: - Buckets

    func loadBuckets(reset: Bool) async {
        guard let tenantId = tenantIdValue else { return }
        if reset {
            bucketsLoading = true
            bucketNextToken = nil
        }
        defer { bucketsLoading = false }
        do {
            let page = try await service.listBuckets(
                tenantId: tenantId,
                limit: 20,
                pageToken: reset ? nil : bucketNextToken
            )
            if reset {
                buckets = page.items
            } else {
                // de-dupe by name
                var seen = Set(buckets.map(\.name))
                for b in page.items where !seen.contains(b.name) {
                    buckets.append(b)
                    seen.insert(b.name)
                }
            }
            bucketNextToken = page.nextPage
            // cache namespace from first bucket if present
            if namespace.isEmpty, let ns = buckets.first?.namespace, !ns.isEmpty {
                namespace = ns
            }
        } catch {
            if reset { buckets = [] }
            handleError(error)
        }
    }

    func refreshBuckets() {
        guard tenantIdValue != nil else {
            ToastCenter.shared.error("请先选择租户")
            return
        }
        Task { await loadBuckets(reset: true) }
    }

    func loadMoreBuckets() {
        guard hasMoreBuckets, !bucketsLoading else { return }
        Task { await loadBuckets(reset: false) }
    }

    func selectBucket(_ item: StorageBucketItem) {
        selectedBucket = item
        if !item.namespace.isEmpty {
            namespace = item.namespace
        }
        Task { await loadObjects(reset: true) }
    }

    func openCreateBucket() {
        guard tenantIdValue != nil else {
            ToastCenter.shared.error("请先选择租户")
            return
        }
        newBucketName = ""
        newBucketAccess = .noPublic
        formError = nil
        formBusy = false
        activeSheet = .createBucket
    }

    func submitCreateBucket() {
        guard let tenantId = tenantIdValue else { return }
        let name = newBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            formError = "请输入存储桶名称"
            return
        }
        formBusy = true
        formError = nil
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.createBucket(
                    tenantId: tenantId,
                    name: name,
                    access: newBucketAccess.rawValue
                )
                activeSheet = nil
                await loadBuckets(reset: true)
            } catch {
                formError = error.localizedDescription
                ToastCenter.shared.error(error.localizedDescription)
            }
            formBusy = false
            LoadingHUD.shared.end()
        }
    }

    func deleteBucket(_ item: StorageBucketItem) {
        guard let tenantId = tenantIdValue else { return }
        guard AppAlert.confirm(
            title: "删除存储桶",
            message: "确定删除「\(item.name)」？桶必须为空才能删除。"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteBucket(
                    tenantId: tenantId,
                    namespace: item.namespace,
                    bucketName: item.name
                )
                if selectedBucket?.name == item.name {
                    clearObjectPanel()
                }
                await loadBuckets(reset: true)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    // MARK: - Objects

    private func clearObjectPanel() {
        selectedBucket = nil
        objects = []
        objectTokens = [nil]
        objectPageIndex = 0
        objectHasNext = false
    }

    func loadObjects(reset: Bool) async {
        guard let tenantId = tenantIdValue,
              let bucket = selectedBucket else { return }
        var useNs = bucket.namespace.isEmpty ? namespace : bucket.namespace
        if useNs.isEmpty {
            do {
                namespace = try await service.getNamespace(tenantId: tenantId)
                useNs = namespace
            } catch {
                handleError(error)
                return
            }
        }
        if useNs.isEmpty {
            ToastCenter.shared.error("无法获取命名空间")
            return
        }

        if reset {
            objectTokens = [nil]
            objectPageIndex = 0
        }
        objectsLoading = true
        defer { objectsLoading = false }

        let token = objectTokens[objectPageIndex]
        do {
            let page = try await service.listObjects(
                tenantId: tenantId,
                namespace: useNs,
                bucketName: bucket.name,
                limit: objectPageLimit,
                startToken: token
            )
            objects = page.items
            if let next = page.nextStartWith, !next.isEmpty {
                if objectTokens.count <= objectPageIndex + 1 {
                    objectTokens.append(next)
                } else {
                    objectTokens[objectPageIndex + 1] = next
                }
                objectHasNext = true
            } else {
                objectHasNext = false
            }
        } catch {
            objects = []
            handleError(error)
        }
    }

    func refreshObjects() {
        guard selectedBucket != nil else { return }
        Task { await loadObjects(reset: false) }
    }

    func objectPrevPage() {
        guard objectPageIndex > 0 else { return }
        objectPageIndex -= 1
        Task { await loadObjects(reset: false) }
    }

    func objectNextPage() {
        guard objectHasNext else { return }
        objectPageIndex += 1
        // ensure token slot
        if objectTokens.count <= objectPageIndex {
            return
        }
        Task { await loadObjects(reset: false) }
    }

    func deleteObject(_ item: StorageObjectItem) {
        guard let tenantId = tenantIdValue, let bucket = selectedBucket else { return }
        let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
        guard AppAlert.confirm(
            title: "删除对象",
            message: "确定删除「\(item.name)」？"
        ) else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                try await service.deleteObject(
                    tenantId: tenantId,
                    namespace: ns,
                    bucketName: bucket.name,
                    objectName: item.name
                )
                await loadObjects(reset: false)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func openPresigned(_ item: StorageObjectItem) {
        guard let tenantId = tenantIdValue, let bucket = selectedBucket else { return }
        let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
        presignedURLText = ""
        activeSheet = .presigned(item)
        Task {
            LoadingHUD.shared.begin()
            do {
                let url = try await service.presignedURL(
                    tenantId: tenantId,
                    namespace: ns,
                    bucketName: bucket.name,
                    objectName: item.name
                )
                presignedURLText = url
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
                activeSheet = nil
            }
            LoadingHUD.shared.end()
        }
    }

    func downloadObject(_ item: StorageObjectItem) {
        guard let tenantId = tenantIdValue, let bucket = selectedBucket else { return }
        let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.displayName
        panel.title = "保存对象"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            LoadingHUD.shared.begin()
            do {
                let (data, _) = try await service.downloadObject(
                    tenantId: tenantId,
                    namespace: ns,
                    bucketName: bucket.name,
                    objectName: item.name
                )
                try data.write(to: dest, options: .atomic)
                AppAlert.info(title: "下载完成", message: dest.path)
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
            LoadingHUD.shared.end()
        }
    }

    func previewObject(_ item: StorageObjectItem) {
        guard let tenantId = tenantIdValue, let bucket = selectedBucket else { return }
        let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
        do {
            let url = try service.objectPreviewURL(
                tenantId: tenantId,
                namespace: ns,
                bucketName: bucket.name,
                objectName: item.name
            )
            NSWorkspace.shared.open(url)
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    // MARK: - Upload

    func pickAndUpload() {
        guard selectedBucket != nil else {
            ToastCenter.shared.error("请先选择存储桶")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择要上传的文件"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        startUpload(files: panel.urls)
    }

    func startUpload(files: [URL]) {
        uploadCancelled = false
        uploadFinished = false
        uploadOverallPercent = 0
        activeUploadId = nil
        uploadTasks = files.map { url in
            var t = StorageUploadTask()
            t.fileName = url.lastPathComponent
            t.fileURL = url
            t.totalBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            t.statusText = "等待中"
            return t
        }
        activeSheet = .uploadProgress
        Task { await runUploadQueue() }
    }

    func cancelUpload() {
        uploadCancelled = true
        if let id = activeUploadId,
           let tenantId = tenantIdValue,
           let bucket = selectedBucket {
            let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
            let objectName = uploadTasks.first(where: { !$0.done && !$0.failed })?.fileName ?? ""
            Task {
                try? await service.abortMultipart(
                    tenantId: tenantId,
                    namespace: ns,
                    bucketName: bucket.name,
                    objectName: objectName,
                    uploadId: id
                )
            }
        }
        activeSheet = nil
    }

    func closeUploadSheet() {
        activeSheet = nil
        if uploadFinished {
            Task { await loadObjects(reset: true) }
        }
    }

    private func runUploadQueue() async {
        guard let tenantId = tenantIdValue, let bucket = selectedBucket else { return }
        let ns = bucket.namespace.isEmpty ? namespace : bucket.namespace
        let total = uploadTasks.count
        guard total > 0 else { return }

        for i in 0..<total {
            if uploadCancelled { break }
            guard let fileURL = uploadTasks[i].fileURL else {
                markTask(i, percent: 0, text: "失败", failed: true)
                continue
            }
            let size = uploadTasks[i].totalBytes
            markTask(i, percent: 0, text: "上传中…", failed: false)
            do {
                if size >= StorageService.multipartThreshold {
                    try await uploadMultipart(
                        index: i,
                        tenantId: tenantId,
                        namespace: ns,
                        bucketName: bucket.name,
                        fileURL: fileURL,
                        totalSize: size
                    )
                } else {
                    try await service.uploadObject(
                        tenantId: tenantId,
                        namespace: ns,
                        bucketName: bucket.name,
                        objectName: fileURL.lastPathComponent,
                        fileURL: fileURL
                    )
                    markTask(i, percent: 100, text: "完成", failed: false, done: true)
                }
            } catch {
                if uploadCancelled {
                    markTask(i, percent: uploadTasks[i].percent, text: "已取消", failed: true)
                    break
                }
                markTask(i, percent: uploadTasks[i].percent, text: "失败", failed: true)
            }
            updateOverall(doneCount: i + 1, total: total)
        }
        uploadFinished = true
        uploadOverallPercent = 100
        if !uploadCancelled {
            await loadObjects(reset: true)
        }
    }

    private func uploadMultipart(
        index: Int,
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        fileURL: URL,
        totalSize: Int64
    ) async throws {
        let objectName = fileURL.lastPathComponent
        let chunkSize = StorageService.chunkSize
        let contentType = mimeType(for: fileURL) ?? "application/octet-stream"
        let uploadId = try await service.initiateMultipart(
            tenantId: tenantId,
            namespace: namespace,
            bucketName: bucketName,
            objectName: objectName,
            contentType: contentType,
            totalSize: totalSize,
            chunkSize: chunkSize
        )
        activeUploadId = uploadId
        defer { activeUploadId = nil }

        let totalParts = Int(ceil(Double(totalSize) / Double(chunkSize)))
        var parts: [(partNum: Int, etag: String)] = []
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        for partNum in 1...max(totalParts, 1) {
            if uploadCancelled {
                try await service.abortMultipart(
                    tenantId: tenantId,
                    namespace: namespace,
                    bucketName: bucketName,
                    objectName: objectName,
                    uploadId: uploadId
                )
                throw APIError.serverMessage("已取消")
            }
            let offset = Int64(partNum - 1) * chunkSize
            let length = min(chunkSize, totalSize - offset)
            if length <= 0 { break }
            if #available(macOS 10.15.4, *) {
                try handle.seek(toOffset: UInt64(offset))
            } else {
                handle.seek(toFileOffset: UInt64(offset))
            }
            let data: Data
            if #available(macOS 10.15.4, *) {
                guard let d = try handle.read(upToCount: Int(length)) else {
                    throw APIError.serverMessage("读取文件失败")
                }
                data = d
            } else {
                data = handle.readData(ofLength: Int(length))
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("oci-part-\(uploadId)-\(partNum).bin")
            try data.write(to: tmp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let part = try await service.uploadPart(
                tenantId: tenantId,
                namespace: namespace,
                bucketName: bucketName,
                objectName: objectName,
                uploadId: uploadId,
                partNumber: partNum,
                chunkURL: tmp
            )
            parts.append(part)
            let pct = Int(Double(partNum) / Double(max(totalParts, 1)) * 100)
            markTask(index, percent: pct, text: "\(pct)%", failed: false)
        }

        try await service.commitMultipart(
            tenantId: tenantId,
            namespace: namespace,
            bucketName: bucketName,
            objectName: objectName,
            uploadId: uploadId,
            parts: parts
        )
        markTask(index, percent: 100, text: "完成", failed: false, done: true)
    }

    private func markTask(_ i: Int, percent: Int, text: String, failed: Bool, done: Bool = false) {
        guard uploadTasks.indices.contains(i) else { return }
        uploadTasks[i].percent = percent
        uploadTasks[i].statusText = text
        uploadTasks[i].failed = failed
        uploadTasks[i].done = done || (!failed && percent >= 100)
    }

    private func updateOverall(doneCount: Int, total: Int) {
        guard total > 0 else { return }
        uploadOverallPercent = min(100, Int(Double(doneCount) / Double(total) * 100))
    }

    private func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "txt", "log", "md": return "text/plain"
        case "html", "htm": return "text/html"
        case "xml": return "application/xml"
        case "zip": return "application/zip"
        default: return nil
        }
    }

    // MARK: - Helpers

    private func handleError(_ error: Error) {
        errorText = error.localizedDescription
        if case APIError.unauthorized = error { return }
        ToastCenter.shared.error(error.localizedDescription)
    }
}
