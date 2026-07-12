import Foundation

enum NetworkError: Error, LocalizedError {
    case unauthorized
    case serverError(String)
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:         return "会话已过期，请重新登录"
        case .serverError(let msg): return msg
        case .invalidURL:           return "服务器地址无效"
        case .invalidResponse:      return "服务器响应无效"
        case .decodingError(let e): return "数据解析失败: \(e.localizedDescription)"
        case .networkError(let e):  return "网络错误: \(e.localizedDescription)"
        }
    }
}

final class NetworkService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    func fetchLoginPage(baseURL: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/login") else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func performLogin(baseURL: String, username: String, encryptedPassword: String,
                      verificationCode: String? = nil, mfaCode: String? = nil) async throws -> LoginSuccessResponse {
        guard let url = URL(string: "\(baseURL)/perform_login") else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var comps = URLComponents()
        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: encryptedPassword)
        ]
        if let vc = verificationCode, !vc.isEmpty { items.append(URLQueryItem(name: "verificationCode", value: vc)) }
        if let mc = mfaCode,          !mc.isEmpty { items.append(URLQueryItem(name: "mfaCode", value: mc)) }
        comps.queryItems = items
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.compatData(for: req)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            let partial = try? JSONDecoder().decode(LoginSuccessResponse.self, from: data)
            throw NetworkError.serverError(partial?.message ?? "用户名或密码错误")
        }
        return try decode(data)
    }

    func sendVerificationCode(baseURL: String, username: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/send-verification-code") else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "username", value: username)]
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (_, _) = try await session.compatData(for: req)
    }

    func fetchLoginConfig(baseURL: String) async throws -> (messageEnabled: Bool, mfaEnabled: Bool) {
        async let msgURL = URL(string: "\(baseURL)/api/config/message-enabled")
        async let mfaURL = URL(string: "\(baseURL)/api/config/mfa-enabled")
        guard let mu = try await msgURL, let mfu = try await mfaURL else { return (false, false) }
        let (md, _) = try await session.compatData(from: mu)
        let (mfd, _) = try await session.compatData(from: mfu)
        let msgOn = (try? JSONDecoder().decode(Bool.self, from: md)) ?? false
        let mfaOn = (try? JSONDecoder().decode(Bool.self, from: mfd)) ?? false
        return (msgOn, mfaOn)
    }

    func performLogout(baseURL: String) async throws {
        guard let url = URL(string: "\(baseURL)/perform_logout") else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        _ = try await session.compatData(for: req)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - Dashboard

    func getDashboardStats(baseURL: String) async throws -> DashboardStats {
        let url = try makeURL("\(baseURL)/boot/dashboard-stats")
        let resp: GenericResponse<DashboardStats> = try await get(url)
        guard let data = resp.data else { throw NetworkError.serverError(resp.message ?? "无数据") }
        return data
    }

    // MARK: - Instances

    func getInstances(baseURL: String, page: Int = 0, size: Int = 100) async throws -> InstanceListResponse {
        let url = try makeURL("\(baseURL)/oci/list/json", params: ["page": "\(page)", "size": "\(size)"])
        return try await get(url)
    }

    func startInstance(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/startInstance"), body: ["instanceId": instanceId])
    }

    func stopInstance(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/stopInstance"), body: ["instanceId": instanceId])
    }

    func terminateInstance(baseURL: String, instanceId: String, verificationCode: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/terminateInstance"), body: [
            "instanceId": instanceId,
            "verificationCode": verificationCode
        ])
    }

    func sendTerminateVerificationCode(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/sendVerificationCode"), body: [
            "instanceId": instanceId
        ])
    }

    func changeIP(baseURL: String, instanceDetailId: String) async throws -> ActionResponse {
        let url = try makeURL("\(baseURL)/oci/changeIp", params: ["tenantId": instanceDetailId])
        return try await get(url)
    }

    func updateInstanceName(baseURL: String, instanceId: String, newName: String) async throws -> ActionResponse {
        struct Body: Encodable { let instanceId: String; let newName: String }
        return try await postJSON(try makeURL("\(baseURL)/oci/updateName"), body: Body(instanceId: instanceId, newName: newName))
    }

    func updateInstanceRemark(baseURL: String, instanceId: String, remark: String) async throws -> ActionResponse {
        struct Body: Encodable { let instanceId: String; let remark: String }
        return try await postJSON(try makeURL("\(baseURL)/oci/updateRemark"), body: Body(instanceId: instanceId, remark: remark))
    }

    func enableIpv6(baseURL: String, instanceDetailId: String) async throws -> ActionResponse {
        // Server returns { status, message } — map via flexible decode
        let url = try makeURL("\(baseURL)/oci/enableIpv6")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(["tenantId": instanceDetailId])
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["status"] as? String) == "success" || (map["success"] as? Bool) == true
            let msg = (map["message"] as? String) ?? (ok ? "IPv6 操作成功" : "IPv6 操作失败")
            return ActionResponse(success: ok, message: msg)
        }
        return try decode(data)
    }

    // MARK: - Tenants

    func getTenants(baseURL: String, page: Int = 0, size: Int = 50,
                    keyword: String? = nil, cloudType: Int? = nil,
                    emailEnable: Int? = nil) async throws -> TenantListResponse {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let kw = keyword, !kw.isEmpty { params["keyword"] = kw }
        if let ct = cloudType { params["cloudType"] = "\(ct)" }
        if let ee = emailEnable { params["emailEnable"] = "\(ee)" }
        let url = try makeURL("\(baseURL)/tenants/list/json", params: params)
        return try await get(url)
    }

    func getAllTenants(baseURL: String) async throws -> [Tenant] {
        let url = try makeURL("\(baseURL)/tenants/listAll")
        let list: [Tenant] = try await get(url)
        return list
    }

    func deleteTenant(baseURL: String, tenantId: Int64) async throws -> ActionResponse {
        // Server: GET /tenants/deleteApi?tenantId=
        let url = try makeURL("\(baseURL)/tenants/deleteApi", params: ["tenantId": "\(tenantId)"])
        // deleteApi returns Map — may not match ActionResponse strictly
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["success"] as? Bool) ?? true
            let msg = (map["message"] as? String) ?? (ok ? "已删除" : "删除失败")
            return ActionResponse(success: ok, message: msg)
        }
        return ActionResponse(success: true, message: "已删除")
    }

    func checkTenantAccounts(baseURL: String) async throws -> AccountCheckResult {
        let url = try makeURL("\(baseURL)/tenants/checkAccounts")
        return try await get(url)
    }

    // MARK: - AI Chat

    func getAiTenants(baseURL: String) async throws -> [AiTenant] {
        let url = try makeURL("\(baseURL)/system/ai/tenants")
        return try await get(url)
    }

    func fetchChatModels(baseURL: String, tenantId: String) async throws -> [AiChatModel] {
        let url = try makeURL("\(baseURL)/system/ai/modelsByTenant", params: ["tenantId": tenantId])
        return try await get(url)
    }

    // MARK: - Object Storage

    func getBuckets(baseURL: String, tenantId: Int64) async throws -> StorageBucketsResponse {
        let url = try makeURL("\(baseURL)/oci/storage/buckets", params: ["tenantId": "\(tenantId)"])
        let resp: GenericResponse<StorageBucketsResponse> = try await get(url)
        return resp.data ?? StorageBucketsResponse(items: [], nextPage: nil)
    }

    func getObjects(baseURL: String, tenantId: Int64, namespace: String, bucketName: String, prefix: String = "") async throws -> StorageObjectsResponse {
        let url = try makeURL("\(baseURL)/oci/storage/objects", params: [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "prefix": prefix
        ])
        let resp: GenericResponse<StorageObjectsResponse> = try await get(url)
        return resp.data ?? StorageObjectsResponse(items: [], nextStartWith: nil)
    }

    func deleteObject(baseURL: String, tenantId: Int64, namespace: String, bucketName: String, objectName: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/storage/object/delete"), body: [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName
        ])
    }

    func downloadURLForObject(baseURL: String, tenantId: Int64, namespace: String, bucketName: String, objectName: String) -> URL? {
        return try? makeURL("\(baseURL)/oci/storage/object/download", params: [
            "tenantId": "\(tenantId)",
            "namespace": namespace,
            "bucketName": bucketName,
            "objectName": objectName
        ])
    }

    // MARK: - Boot tasks (reuse mobile JSON APIs under /m)

    func getBootTasks(baseURL: String, page: Int = 0, size: Int = 100) async throws -> BootTaskListData {
        let url = try makeURL("\(baseURL)/m/api/boot", params: ["page": "\(page)", "size": "\(size)"])
        let resp: GenericResponse<BootTaskListData> = try await get(url)
        return resp.data ?? BootTaskListData(list: [], total: 0, runningCount: 0)
    }

    func startBootTask(baseURL: String, bootId: Int64) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/m/api/boot/\(bootId)/start"), body: [:])
    }

    func stopBootTask(baseURL: String, bootId: Int64) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/m/api/boot/\(bootId)/stop"), body: [:])
    }

    func deleteBootTask(baseURL: String, bootId: Int64) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/m/api/boot/\(bootId)/delete"), body: [:])
    }

    func batchStartBoots(baseURL: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/boot/batchStart"), body: [:])
    }

    func batchStopBoots(baseURL: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/boot/batchStop"), body: [:])
    }

    // MARK: - Object storage write

    func createBucket(baseURL: String, tenantId: Int64, bucketName: String, publicAccessType: String = "NoPublicAccess") async throws -> ActionResponse {
        struct Body: Encodable {
            let tenantId: Int64
            let bucketName: String
            let publicAccessType: String
        }
        return try await postJSON(try makeURL("\(baseURL)/oci/storage/bucket/create"),
                                  body: Body(tenantId: tenantId, bucketName: bucketName, publicAccessType: publicAccessType))
    }

    func uploadObject(baseURL: String, tenantId: Int64, namespace: String, bucketName: String,
                      objectName: String?, fileURL: URL) async throws -> ActionResponse {
        let url = try makeURL("\(baseURL)/oci/storage/object/upload")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let objName = (objectName?.isEmpty == false) ? objectName! : filename

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("tenantId", "\(tenantId)")
        appendField("namespace", namespace)
        appendField("bucketName", bucketName)
        appendField("objectName", objName)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["success"] as? Bool) ?? false
            let msg = (map["message"] as? String) ?? (ok ? "上传成功" : "上传失败")
            return ActionResponse(success: ok, message: msg)
        }
        return try decode(data)
    }

    // MARK: - VPS Monitor
    // Web VPS list uses same instance source; ping APIs are batch (no body).

    func getVpsInstances(baseURL: String, page: Int = 0, size: Int = 1000) async throws -> InstanceListResponse {
        let url = try makeURL("\(baseURL)/oci/list/json", params: ["page": "\(page)", "size": "\(size)"])
        return try await get(url)
    }

    func pingInstances(baseURL: String) async throws -> ActionResponse {
        return try await postFlexible(try makeURL("\(baseURL)/vps/instances/ping"))
    }

    func enablePingBatch(baseURL: String) async throws -> ActionResponse {
        return try await postFlexible(try makeURL("\(baseURL)/vps/instances/enablePing"))
    }

    func disablePingBatch(baseURL: String) async throws -> ActionResponse {
        return try await postFlexible(try makeURL("\(baseURL)/vps/instances/disablePing"))
    }

    /// ApiResponse may use success+message without matching ActionResponse strictly
    private func postFlexible(_ url: URL) async throws -> ActionResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["success"] as? Bool) ?? true
            let msg = (map["message"] as? String) ?? (ok ? "完成" : "失败")
            return ActionResponse(success: ok, message: msg)
        }
        return ActionResponse(success: true, message: "完成")
    }

    // MARK: - Notify configs load

    func getNotifyConfigs(baseURL: String) async throws -> NotifyConfigsBundle {
        let url = try makeURL("\(baseURL)/api/system/notifyConfigs")
        let resp: GenericResponse<NotifyConfigsBundle> = try await get(url)
        return resp.data ?? NotifyConfigsBundle()
    }

    // MARK: - Memos

    func getMemos(baseURL: String) async throws -> [Memo] {
        let url = try makeURL("\(baseURL)/api/memos")
        return try await get(url)
    }

    func createMemo(baseURL: String, title: String, content: String) async throws -> Memo {
        let url = try makeURL("\(baseURL)/api/memos")
        return try await postJSON(url, body: ["title": title, "content": content])
    }

    func updateMemo(baseURL: String, id: Int64, title: String, content: String) async throws -> Memo {
        let url = try makeURL("\(baseURL)/api/memos/\(id)")
        return try await putJSON(url, body: ["title": title, "content": content])
    }

    func deleteMemo(baseURL: String, id: Int64) async throws {
        let url = try makeURL("\(baseURL)/api/memos/\(id)")
        _ = try await delete(url)
    }

    // MARK: - API Token

    func getApiTokenStatus(baseURL: String) async throws -> ApiTokenStatus {
        let url = try makeURL("\(baseURL)/api/system/apiTokenStatus")
        let resp: GenericResponse<ApiTokenStatus> = try await get(url)
        return resp.data ?? ApiTokenStatus(token: nil, enabled: false, createdAt: nil, description: nil, tokenName: nil)
    }

    func generateApiToken(baseURL: String) async throws -> ApiTokenStatus {
        let url = try makeURL("\(baseURL)/api/system/generateApiToken")
        let resp: GenericResponse<ApiTokenStatus> = try await post(url, body: [:])
        return resp.data ?? ApiTokenStatus(token: nil, enabled: false, createdAt: nil, description: nil, tokenName: nil)
    }

    func revokeApiToken(baseURL: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/api/system/revokeApiToken"), body: [:])
    }

    // MARK: - System Settings

    func updatePassword(baseURL: String, oldPassword: String, newPassword: String) async throws -> ActionResponse {
        struct Body: Encodable { let oldPassword: String; let newPassword: String }
        return try await postJSONAction(
            try makeURL("\(baseURL)/api/system/updatePassword"),
            body: Body(oldPassword: oldPassword, newPassword: newPassword))
    }

    func updateTelegramConfig(baseURL: String, enabled: Bool, botToken: String, chatId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/api/system/updateTelegramConfig"), body: [
            "enabled": enabled ? "true" : "false",
            "botToken": botToken,
            "chatId": chatId
        ])
    }

    func testTelegram(baseURL: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/api/system/testTgTalk"), body: [:])
    }

    // MARK: - ARM Records

    func getArmData(baseURL: String) async throws -> [ArmRegionRecord] {
        let url = try makeURL("\(baseURL)/resource/arm-data")
        let resp: GenericResponse<[String: AnyCodable]> = try await get(url)
        // armRecords is nested inside the data
        if let dataMap = resp.data,
           let records = dataMap["armRecords"]?.value as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: records)
            return try JSONDecoder().decode([ArmRegionRecord].self, from: jsonData)
        }
        return []
    }

    // MARK: - Boot

    func listRegions(baseURL: String, tenantId: Int64) async throws -> [RegionItem] {
        let url = try makeURL("\(baseURL)/tenants/listRegions", params: ["parentId": "\(tenantId)"])
        return try await get(url)
    }

    func querySystemImages(baseURL: String, tenantId: Int64, shapeType: String) async throws -> [SystemImage] {
        struct Req: Encodable { let tenantId: Int64; let shapeType: String }
        let url = try makeURL("\(baseURL)/tenants/querySystemImages")
        let resp: GenericResponse<[SystemImage]> = try await postJSON(url, body: Req(tenantId: tenantId, shapeType: shapeType))
        return resp.data ?? []
    }

    func saveBootConfig(baseURL: String, params: [String: String]) async throws -> ActionResponse {
        let url = try makeURL("\(baseURL)/tenants/boot/save")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if data.isEmpty { return ActionResponse(success: true, message: "实例创建成功") }
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["success"] as? Bool) ?? true
            let msg = (map["message"] as? String) ?? (ok ? "实例创建成功" : "创建失败")
            return ActionResponse(success: ok, message: msg)
        }
        return (try? decode(data)) ?? ActionResponse(success: true, message: "实例创建成功")
    }

    // MARK: - Cloudflare DNS

    func cfZones(baseURL: String) async throws -> [[String: Any]] {
        try await apiDataArray(try makeURL("\(baseURL)/dns/cloudflare/api/zones"))
    }

    func cfRecords(baseURL: String, zoneId: String, page: Int = 1, size: Int = 50) async throws -> [[String: Any]] {
        let url = try makeURL("\(baseURL)/dns/cloudflare/api/zones/\(zoneId)/records",
                              params: ["page": "\(page)", "size": "\(size)"])
        let data = try await apiDataAny(url)
        // paginated map may contain result/records/list/content
        if let arr = data as? [[String: Any]] { return arr }
        if let map = data as? [String: Any] {
            for key in ["result", "records", "list", "content", "items", "data"] {
                if let arr = map[key] as? [[String: Any]] { return arr }
            }
        }
        return []
    }

    func cfAddRecord(baseURL: String, zoneId: String, type: String, name: String,
                     content: String, ttl: Int, proxied: Bool) async throws -> ActionResponse {
        struct Body: Encodable {
            let zoneId: String; let type: String; let name: String
            let content: String; let ttl: Int; let proxied: Bool
        }
        return try await postJSONAction(try makeURL("\(baseURL)/dns/cloudflare/api/records"),
                                        body: Body(zoneId: zoneId, type: type, name: name,
                                                   content: content, ttl: ttl, proxied: proxied))
    }

    func cfUpdateRecord(baseURL: String, recordId: String, zoneId: String,
                        type: String, name: String, content: String,
                        ttl: Int, proxied: Bool) async throws -> ActionResponse {
        struct Body: Encodable {
            let zoneId: String; let recordType: String; let recordName: String
            let content: String; let ttl: Int; let proxied: Bool
        }
        return try await putJSONAction(
            try makeURL("\(baseURL)/dns/cloudflare/api/records/\(recordId)"),
            body: Body(zoneId: zoneId, recordType: type, recordName: name,
                       content: content, ttl: ttl, proxied: proxied))
    }

    func cfDeleteRecord(baseURL: String, recordId: String, zoneId: String?) async throws -> ActionResponse {
        var params: [String: String] = [:]
        if let z = zoneId { params["zoneId"] = z }
        let url = try makeURL("\(baseURL)/dns/cloudflare/api/records/\(recordId)", params: params)
        return try await deleteAction(url)
    }

    func cfSyncZone(baseURL: String, zoneId: String, domainName: String) async throws -> ActionResponse {
        struct Body: Encodable { let domainName: String }
        return try await postJSONAction(
            try makeURL("\(baseURL)/dns/cloudflare/api/zones/\(zoneId)/sync"),
            body: Body(domainName: domainName))
    }

    // MARK: - EdgeOne DNS

    func eoZones(baseURL: String) async throws -> [[String: Any]] {
        try await apiDataArray(try makeURL("\(baseURL)/dns/edgeone/api/zones"))
    }

    func eoRecords(baseURL: String, zoneId: String) async throws -> [[String: Any]] {
        let url = try makeURL("\(baseURL)/dns/edgeone/api/records",
                              params: ["zoneId": zoneId, "type": "dns"])
        return try await apiDataArray(url)
    }

    func eoAddRecord(baseURL: String, zoneId: String, type: String, name: String,
                     content: String, ttl: Int) async throws -> ActionResponse {
        struct Body: Encodable {
            let zoneId: String; let type: String; let name: String
            let content: String; let ttl: Int
        }
        return try await postJSONAction(try makeURL("\(baseURL)/dns/edgeone/api/records"),
                                        body: Body(zoneId: zoneId, type: type, name: name,
                                                   content: content, ttl: ttl))
    }

    func eoUpdateRecord(baseURL: String, recordId: String, zoneId: String,
                        type: String, name: String, content: String, ttl: Int) async throws -> ActionResponse {
        struct Body: Encodable {
            let zoneId: String; let recordType: String; let recordName: String
            let content: String; let ttl: Int
        }
        return try await putJSONAction(
            try makeURL("\(baseURL)/dns/edgeone/api/records/\(recordId)"),
            body: Body(zoneId: zoneId, recordType: type, recordName: name, content: content, ttl: ttl))
    }

    func eoDeleteRecord(baseURL: String, recordId: String) async throws -> ActionResponse {
        try await deleteAction(try makeURL("\(baseURL)/dns/edgeone/api/records/\(recordId)"))
    }

    func eoSyncZone(baseURL: String, zoneId: String, domainName: String) async throws -> ActionResponse {
        struct Body: Encodable { let domainName: String }
        return try await postJSONAction(
            try makeURL("\(baseURL)/dns/edgeone/api/zones/\(zoneId)/sync"),
            body: Body(domainName: domainName))
    }

    // MARK: - IP quality settings

    func getIpSettingsConfigs(baseURL: String) async throws -> IpSettingsBundle {
        let url = try makeURL("\(baseURL)/api/system/ipSettingsConfigs")
        let resp: GenericResponse<IpSettingsBundle> = try await get(url)
        guard let data = resp.data else { throw NetworkError.serverError(resp.message ?? "无数据") }
        return data
    }

    func updateIpCheckConfig(baseURL: String, enabled: Bool, checkInterval: Int) async throws -> ActionResponse {
        struct Body: Encodable { let enabled: Bool; let checkInterval: Int }
        return try await postJSONAction(try makeURL("\(baseURL)/api/system/updateIpCheckConfig"),
                                        body: Body(enabled: enabled, checkInterval: checkInterval))
    }

    func saveOperatorVpsConfig(baseURL: String, type: String, enabled: Bool,
                               serverIp: String, username: String,
                               sshPort: Int, password: String) async throws -> ActionResponse {
        struct Body: Encodable {
            let type: String; let enabled: Bool; let serverIp: String
            let username: String; let sshPort: Int; let password: String
        }
        return try await postJSONAction(try makeURL("\(baseURL)/system/vps/saveConfig"),
                                        body: Body(type: type, enabled: enabled, serverIp: serverIp,
                                                   username: username, sshPort: sshPort, password: password))
    }

    func testOperatorVpsConnection(baseURL: String, type: String, serverIp: String,
                                   username: String, sshPort: Int, password: String) async throws -> ActionResponse {
        struct Body: Encodable {
            let type: String; let serverIp: String; let username: String
            let sshPort: Int; let password: String
        }
        return try await postJSONAction(try makeURL("\(baseURL)/system/vps/testConnection"),
                                        body: Body(type: type, serverIp: serverIp, username: username,
                                                   sshPort: sshPort, password: password))
    }

    // MARK: - VPN proxy

    func vpnProxyList(baseURL: String, pageNum: Int = 1, pageSize: Int = 50) async throws -> [[String: Any]] {
        struct Body: Encodable { let pageNum: Int; let pageSize: Int }
        let data = try await postJSONAny(try makeURL("\(baseURL)/vpnProxy/pageList"),
                                         body: Body(pageNum: pageNum, pageSize: pageSize))
        return pageContent(data)
    }

    func vpnProxySave(baseURL: String, id: Int64?, proxyType: String, proxyHost: String,
                      proxyPort: Int, proxyUsername: String?, proxyPassword: String?,
                      availableStatus: Int) async throws -> ActionResponse {
        struct Body: Encodable {
            let id: Int64?
            let proxyType: String
            let proxyHost: String
            let proxyPort: Int
            let proxyUsername: String?
            let proxyPassword: String?
            let availableStatus: Int
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/vpnProxy/saveOrUpdate"),
            body: Body(id: id, proxyType: proxyType, proxyHost: proxyHost, proxyPort: proxyPort,
                       proxyUsername: proxyUsername, proxyPassword: proxyPassword,
                       availableStatus: availableStatus))
    }

    func vpnProxyDelete(baseURL: String, id: Int64) async throws -> ActionResponse {
        struct Body: Encodable { let id: Int64 }
        return try await postJSONAction(try makeURL("\(baseURL)/vpnProxy/delete"),
                                        body: Body(id: id))
    }

    // MARK: - Domain provider keys (CF / EdgeOne)

    func getDomainProviderConfigs(baseURL: String) async throws -> DomainProviderBundle {
        let url = try makeURL("\(baseURL)/api/system/domainProviderConfigs")
        let resp: GenericResponse<DomainProviderBundle> = try await get(url)
        guard let data = resp.data else { throw NetworkError.serverError(resp.message ?? "无数据") }
        return data
    }

    func updateCloudflareConfig(baseURL: String, enabled: Bool, apiToken: String,
                                email: String, zoneId: String = "") async throws -> ActionResponse {
        struct Body: Encodable {
            let enabled: Bool; let apiToken: String; let email: String; let zoneId: String
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/api/system/updateCloudflareConfig"),
            body: Body(enabled: enabled, apiToken: apiToken, email: email, zoneId: zoneId))
    }

    func testCloudflareConfig(baseURL: String, enabled: Bool, apiToken: String,
                              email: String, zoneId: String = "") async throws -> ActionResponse {
        struct Body: Encodable {
            let enabled: Bool; let apiToken: String; let email: String; let zoneId: String
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/api/system/testCloudflareConnection"),
            body: Body(enabled: enabled, apiToken: apiToken, email: email, zoneId: zoneId))
    }

    func updateEdgeOneConfig(baseURL: String, enabled: Bool, secretId: String,
                             secretKey: String, region: String = "ap-beijing") async throws -> ActionResponse {
        struct Body: Encodable {
            let enabled: Bool; let secretId: String; let secretKey: String; let region: String
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/api/system/updateEdgeOneConfig"),
            body: Body(enabled: enabled, secretId: secretId, secretKey: secretKey, region: region))
    }

    func testEdgeOneConfig(baseURL: String, enabled: Bool, secretId: String,
                           secretKey: String, region: String = "ap-beijing") async throws -> ActionResponse {
        struct Body: Encodable {
            let enabled: Bool; let secretId: String; let secretKey: String; let region: String
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/api/system/testEdgeOneConnection"),
            body: Body(enabled: enabled, secretId: secretId, secretKey: secretKey, region: region))
    }

    // MARK: - Email

    func emailReceiveList(baseURL: String, pageNum: Int = 1, pageSize: Int = 50) async throws -> [[String: Any]] {
        struct Body: Encodable { let pageNum: Int; let pageSize: Int }
        let data = try await postJSONAny(try makeURL("\(baseURL)/email/receive/list"),
                                         body: Body(pageNum: pageNum, pageSize: pageSize))
        return pageContent(data)
    }

    func emailReceiveAdd(baseURL: String, name: String, email: String) async throws -> ActionResponse {
        struct Body: Encodable { let name: String; let email: String }
        return try await postJSONAction(try makeURL("\(baseURL)/email/receive/add"),
                                        body: Body(name: name, email: email))
    }

    func emailReceiveDelete(baseURL: String, id: Int64) async throws -> ActionResponse {
        // Server: @RequestParam Long id
        let url = try makeURL("\(baseURL)/email/receive/delete", params: ["id": "\(id)"])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if data.isEmpty { return ActionResponse(success: true, message: "删除成功") }
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ActionResponse(success: (map["success"] as? Bool) ?? true,
                                  message: map["message"] as? String)
        }
        return ActionResponse(success: true, message: "删除成功")
    }

    func emailTenantConfigs(baseURL: String, pageNum: Int = 1, pageSize: Int = 100) async throws -> [[String: Any]] {
        struct Body: Encodable { let pageNum: Int; let pageSize: Int }
        let data = try await postJSONAny(try makeURL("\(baseURL)/email/tenant/list"),
                                         body: Body(pageNum: pageNum, pageSize: pageSize))
        return pageContent(data)
    }

    func emailBodyList(baseURL: String, pageNum: Int = 1, pageSize: Int = 50) async throws -> [[String: Any]] {
        struct Body: Encodable {
            let pageNum: Int; let pageSize: Int; let sort: String; let order: String
        }
        let data = try await postJSONAny(try makeURL("\(baseURL)/email/body/list"),
                                         body: Body(pageNum: pageNum, pageSize: pageSize,
                                                    sort: "createTime", order: "desc"))
        return pageContent(data)
    }

    func emailSendRecords(baseURL: String, emailBodyId: String,
                          pageNum: Int = 1, pageSize: Int = 50) async throws -> [[String: Any]] {
        struct Body: Encodable {
            let emailBodyId: String; let pageNum: Int; let pageSize: Int
            let sort: String; let order: String
        }
        let data = try await postJSONAny(try makeURL("\(baseURL)/email/send/list"),
                                         body: Body(emailBodyId: emailBodyId, pageNum: pageNum,
                                                    pageSize: pageSize, sort: "createTime", order: "desc"))
        return pageContent(data)
    }

    func emailSend(baseURL: String, title: String, content: String,
                   tenantEmailConfigId: Int64, emailReceiveIds: [Int64]) async throws -> ActionResponse {
        struct Body: Encodable {
            let title: String; let content: String
            let tenantEmailConfigId: Int64; let emailReceiveIds: [Int64]
        }
        return try await postJSONAction(
            try makeURL("\(baseURL)/email/send"),
            body: Body(title: title, content: content,
                       tenantEmailConfigId: tenantEmailConfigId, emailReceiveIds: emailReceiveIds))
    }

    func emailBodyDelete(baseURL: String, id: Int64) async throws -> ActionResponse {
        struct Body: Encodable { let id: Int64 }
        return try await postJSONAction(try makeURL("\(baseURL)/email/body/delete"),
                                        body: Body(id: id))
    }

    /// Disable email service for a TenantEmailConfig row (`id` = config primary key).
    func emailConfigDisable(baseURL: String, configId: Int64) async throws -> ActionResponse {
        struct Body: Encodable { let id: Int64 }
        return try await postJSONAction(try makeURL("\(baseURL)/email/disable"),
                                        body: Body(id: configId))
    }

    /// Enable OCI email for tenant (`tenantId` = tenants table id).
    func enableTenantEmail(baseURL: String, tenantId: Int64, emailDomain: String) async throws -> ActionResponse {
        struct Body: Encodable { let tenantId: Int64; let emailDomain: String }
        return try await postJSONAction(try makeURL("\(baseURL)/tenants/email/enable"),
                                        body: Body(tenantId: tenantId, emailDomain: emailDomain))
    }

    // MARK: - ApiResponse helpers (dynamic JSON)

    private func apiEnvelope(_ data: Data) throws -> (ok: Bool, message: String?, data: Any?) {
        guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse
        }
        let ok = (map["success"] as? Bool) ?? true
        let msg = map["message"] as? String
        if !ok { throw NetworkError.serverError(msg ?? "请求失败") }
        return (ok, msg, map["data"])
    }

    private func apiDataAny(_ url: URL) async throws -> Any? {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        return try apiEnvelope(data).data
    }

    private func apiDataArray(_ url: URL) async throws -> [[String: Any]] {
        let data = try await apiDataAny(url)
        if let arr = data as? [[String: Any]] { return arr }
        return []
    }

    private func postJSONAny<B: Encodable>(_ url: URL, body: B) async throws -> Any? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        return try apiEnvelope(data).data
    }

    private func putJSONAction<B: Encodable>(_ url: URL, body: B) async throws -> ActionResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if data.isEmpty { return ActionResponse(success: true, message: "ok") }
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ActionResponse(success: (map["success"] as? Bool) ?? true,
                                  message: map["message"] as? String)
        }
        return ActionResponse(success: true, message: "ok")
    }

    private func deleteAction(_ url: URL) async throws -> ActionResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if data.isEmpty { return ActionResponse(success: true, message: "ok") }
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ActionResponse(success: (map["success"] as? Bool) ?? true,
                                  message: map["message"] as? String)
        }
        return ActionResponse(success: true, message: "ok")
    }

    private func pageContent(_ data: Any?) -> [[String: Any]] {
        guard let data = data else { return [] }
        if let arr = data as? [[String: Any]] { return arr }
        if let map = data as? [String: Any] {
            for key in ["content", "list", "records", "items"] {
                if let arr = map[key] as? [[String: Any]] { return arr }
            }
        }
        return []
    }

    // MARK: - Speed test / IP

    func getOracleEndpoints(baseURL: String) async throws -> [[String: Any]] {
        try await apiDataArray(try makeURL("\(baseURL)/api/getOracleEndpoint"))
    }

    func getCurrentIpDisplay(baseURL: String) async throws -> String {
        let data = try await apiDataAny(try makeURL("\(baseURL)/api/getCurrentIp"))
        if let s = data as? String { return s }
        return "—"
    }

    // MARK: - Migration file transfer

    func downloadMigrationExport(baseURL: String) async throws -> (Data, String) {
        let url = try makeURL("\(baseURL)/migration/export")
        var req = URLRequest(url: url)
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        let name = suggestedFilename(from: response) ?? "oci-start_backup.sql"
        return (data, name)
    }

    func downloadMigrationExportEncrypted(baseURL: String) async throws -> (Data, String, String?) {
        let url = try makeURL("\(baseURL)/migration/exportEncrypted")
        var req = URLRequest(url: url)
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        var masterKey: String?
        if let http = response as? HTTPURLResponse {
            masterKey = http.value(forHTTPHeaderField: "master-key")
                ?? http.value(forHTTPHeaderField: "Master-Key")
                ?? http.value(forHTTPHeaderField: "X-Master-Key")
        }
        let name = suggestedFilename(from: response) ?? "oci-start_backup.enc"
        return (data, name, masterKey)
    }

    func importMigrationSQL(baseURL: String, fileURL: URL) async throws -> String {
        try await multipartUpload(
            url: try makeURL("\(baseURL)/migration/import"),
            fileURL: fileURL,
            fieldName: "file",
            extraFields: [:])
    }

    func importMigrationEncrypted(baseURL: String, fileURL: URL, masterKey: String) async throws -> String {
        try await multipartUpload(
            url: try makeURL("\(baseURL)/migration/importEncrypted"),
            fileURL: fileURL,
            fieldName: "file",
            extraFields: ["masterKey": masterKey])
    }

    private func multipartUpload(url: URL, fileURL: URL, fieldName: String,
                                 extraFields: [String: String]) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        var body = Data()
        for (k, v) in extraFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(v)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, response) = try await session.compatData(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "导入失败"
            throw NetworkError.serverError(msg)
        }
        return String(data: data, encoding: .utf8) ?? "导入成功"
    }

    private func suggestedFilename(from response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse,
              let cd = http.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        // filename="..."
        if let r = cd.range(of: "filename=\"") {
            let rest = cd[r.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                return String(rest[..<end])
            }
        }
        if let r = cd.range(of: "filename=") {
            return String(cd[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Generic HTTP helpers

    func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        do {
            let (data, response) = try await session.compatData(for: req)
            try checkHTTP(response)
            return try decode(data)
        } catch let e as NetworkError { throw e }
        catch { throw NetworkError.networkError(error) }
    }

    func post<T: Decodable>(_ url: URL, body: [String: String]) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.compatData(for: req)
            try checkHTTP(response)
            return try decode(data)
        } catch let e as NetworkError { throw e }
        catch { throw NetworkError.networkError(error) }
    }

    func postJSON<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.compatData(for: req)
            try checkHTTP(response)
            return try decode(data)
        } catch let e as NetworkError { throw e }
        catch { throw NetworkError.networkError(error) }
    }

    /// POST JSON; empty 200 body is treated as success (many system config endpoints return no body).
    func postJSONAction<B: Encodable>(_ url: URL, body: B) async throws -> ActionResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        let (data, response) = try await session.compatData(for: req)
        try checkHTTP(response)
        if data.isEmpty { return ActionResponse(success: true, message: "ok") }
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ok = (map["success"] as? Bool) ?? true
            let msg = (map["message"] as? String) ?? "ok"
            return ActionResponse(success: ok, message: msg)
        }
        return (try? decode(data)) ?? ActionResponse(success: true, message: "ok")
    }

    private func putJSON<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = try? JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.compatData(for: req)
            try checkHTTP(response)
            return try decode(data)
        } catch let e as NetworkError { throw e }
        catch { throw NetworkError.networkError(error) }
    }

    private func delete(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        do {
            let (data, response) = try await session.compatData(for: req)
            try checkHTTP(response)
            return data
        } catch let e as NetworkError { throw e }
        catch { throw NetworkError.networkError(error) }
    }

    func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 302 { throw NetworkError.unauthorized }
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let html = String(data: data, encoding: .utf8), html.contains("<html") {
                throw NetworkError.unauthorized
            }
            throw NetworkError.decodingError(error)
        }
    }

    func makeURL(_ base: String, params: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(string: base) else { throw NetworkError.invalidURL }
        if !params.isEmpty {
            comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw NetworkError.invalidURL }
        return url
    }
}

// Helper for decoding arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else if let v = try? container.decode([AnyCodable].self) { value = v.map { $0.value } }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}
