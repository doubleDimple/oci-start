import Foundation

/// Network layer for `/oci/storage/*` (+ parent tenants for selector).
struct StorageService {
    let baseURL: String
    private let client = APIClient.shared

    // MARK: - Tenants

    func listParentTenants() async throws -> [TenantRegionOption] {
        let url = try client.makeURL(baseURL, path: "/tenants/listParentTenants")
        let raw = try await client.getJSON(url)
        return (try? JSONDecoder().decode([TenantRegionOption].self, from: raw)) ?? []
    }

    // MARK: - Namespace / Buckets

    func getNamespace(tenantId: Int64) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/storage/namespace", query: [
            "tenantId": "\(tenantId)"
        ])
        let raw = try await client.getJSON(url)
        let data = try StorageJSON.envelopeData(raw)
        if let dict = data as? [String: Any] {
            let ns = StorageJSON.string(dict["namespace"])
            if !ns.isEmpty { return ns }
        }
        if let s = data as? String, !s.isEmpty { return s }
        throw APIError.serverMessage("获取命名空间失败")
    }

    func listBuckets(tenantId: Int64, limit: Int = 5, pageToken: String?) async throws -> StorageBucketPage {
        var q: [String: String] = [
            "tenantId": "\(tenantId)",
            "limit": "\(limit)"
        ]
        if let pageToken = pageToken, !pageToken.isEmpty {
            q["pageToken"] = pageToken
        }
        let url = try client.makeURL(baseURL, path: "/oci/storage/buckets", query: q)
        let raw = try await client.getJSON(url)
        return try StorageJSON.parseBucketPage(raw)
    }

    func createBucket(tenantId: Int64, name: String, access: String) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/bucket/create")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "bucketName": name,
            "publicAccessType": access
        ])
        try StorageJSON.ensureSuccess(raw, fallback: "创建存储桶失败")
    }

    func deleteBucket(tenantId: Int64, namespace: String, bucketName: String) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/bucket/delete")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName
        ])
        try StorageJSON.ensureSuccess(raw, fallback: "删除存储桶失败")
    }

    // MARK: - Objects

    func listObjects(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        prefix: String = "",
        limit: Int = 5,
        startToken: String?
    ) async throws -> StorageObjectPage {
        var q: [String: String] = [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "limit": "\(limit)"
        ]
        if !prefix.isEmpty { q["prefix"] = prefix }
        if let startToken = startToken, !startToken.isEmpty {
            q["startToken"] = startToken
        }
        let url = try client.makeURL(baseURL, path: "/oci/storage/objects", query: q)
        let raw = try await client.getJSON(url)
        return try StorageJSON.parseObjectPage(raw)
    }

    func deleteObject(tenantId: Int64, namespace: String, bucketName: String, objectName: String) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/delete")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName
        ])
        try StorageJSON.ensureSuccess(raw, fallback: "删除对象失败")
    }

    func presignedURL(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String,
        validitySeconds: Int64 = 3600
    ) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/presigned")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName,
            "validitySeconds": validitySeconds
        ])
        let data = try StorageJSON.envelopeData(raw)
        if let dict = data as? [String: Any] {
            let u = StorageJSON.string(dict["url"])
            if !u.isEmpty { return u }
        }
        if let s = data as? String, !s.isEmpty { return s }
        throw APIError.serverMessage("生成预签名 URL 失败")
    }

    /// Simple upload (`/object/upload`) — suitable for smaller files.
    func uploadObject(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String?,
        fileURL: URL
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/upload")
        var fields: [String: String] = [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName
        ]
        if let objectName = objectName, !objectName.isEmpty {
            fields["objectName"] = objectName
        }
        let raw = try await client.postMultipart(
            url,
            fields: fields,
            fileFieldName: "file",
            fileURL: fileURL
        )
        try StorageJSON.ensureSuccess(raw, fallback: "上传失败")
    }

    /// Download object bytes (+ optional suggested filename).
    func downloadObject(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String
    ) async throws -> (Data, String?) {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/download", query: [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName
        ])
        return try await client.download(url)
    }

    /// Absolute URL for preview/download in external browser (session cookie applies if same host).
    func objectPreviewURL(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String
    ) throws -> URL {
        try client.makeURL(baseURL, path: "/oci/storage/object/preview", query: [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName
        ])
    }

    // MARK: - Multipart (large files)

    static let multipartThreshold: Int64 = 50 * 1024 * 1024
    static let chunkSize: Int64 = 10 * 1024 * 1024

    func initiateMultipart(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String,
        contentType: String?,
        totalSize: Int64,
        chunkSize: Int64
    ) async throws -> String {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/multipart/initiate")
        var body: [String: Any] = [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName,
            "totalSize": totalSize,
            "chunkSize": chunkSize
        ]
        if let contentType = contentType, !contentType.isEmpty {
            body["contentType"] = contentType
        }
        let raw = try await client.postJSON(url, body: body)
        let data = try StorageJSON.envelopeData(raw)
        if let dict = data as? [String: Any] {
            let id = StorageJSON.string(dict["uploadId"])
            if !id.isEmpty { return id }
        }
        throw APIError.serverMessage("初始化分片上传失败")
    }

    func uploadPart(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String,
        uploadId: String,
        partNumber: Int,
        chunkURL: URL
    ) async throws -> (partNum: Int, etag: String) {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/multipart/part")
        let raw = try await client.postMultipart(
            url,
            fields: [
                "tenantId": "\(tenantId)",
                "namespace": namespace,
                "bucketName": bucketName,
                "objectName": objectName,
                "uploadId": uploadId,
                "partNumber": "\(partNumber)"
            ],
            fileFieldName: "chunk",
            fileURL: chunkURL
        )
        let data = try StorageJSON.envelopeData(raw)
        guard let dict = data as? [String: Any] else {
            throw APIError.serverMessage("分片上传响应无效")
        }
        let partNum = Int(StorageJSON.int64(dict["partNum"]))
        let etag = StorageJSON.string(dict["etag"])
        if etag.isEmpty { throw APIError.serverMessage("分片上传失败") }
        return (partNum > 0 ? partNum : partNumber, etag)
    }

    func commitMultipart(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String,
        uploadId: String,
        parts: [(partNum: Int, etag: String)]
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/multipart/commit")
        let partsBody: [[String: Any]] = parts.map { ["partNum": $0.partNum, "etag": $0.etag] }
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName,
            "uploadId": uploadId,
            "parts": partsBody
        ])
        try StorageJSON.ensureSuccess(raw, fallback: "提交分片失败")
    }

    func abortMultipart(
        tenantId: Int64,
        namespace: String,
        bucketName: String,
        objectName: String,
        uploadId: String
    ) async throws {
        let url = try client.makeURL(baseURL, path: "/oci/storage/object/multipart/abort")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName,
            "uploadId": uploadId
        ])
        try StorageJSON.ensureSuccess(raw, fallback: "取消上传失败")
    }
}
