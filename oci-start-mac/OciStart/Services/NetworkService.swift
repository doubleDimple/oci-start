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

    func terminateInstance(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/oci/terminateInstance"), body: ["instanceId": instanceId])
    }

    func changeIP(baseURL: String, instanceDetailId: String) async throws -> ActionResponse {
        let url = try makeURL("\(baseURL)/oci/changeIp", params: ["tenantId": instanceDetailId])
        return try await get(url)
    }

    // MARK: - Tenants

    func getTenants(baseURL: String, page: Int = 0, size: Int = 50, keyword: String? = nil) async throws -> TenantListResponse {
        var params: [String: String] = ["page": "\(page)", "size": "\(size)"]
        if let kw = keyword, !kw.isEmpty { params["keyword"] = kw }
        let url = try makeURL("\(baseURL)/tenants/list/json", params: params)
        return try await get(url)
    }

    func getAllTenants(baseURL: String) async throws -> [Tenant] {
        let url = try makeURL("\(baseURL)/tenants/listAll")
        let list: [Tenant] = try await get(url)
        return list
    }

    func deleteTenant(baseURL: String, tenantId: Int64) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/tenants/delete"), body: ["id": "\(tenantId)"])
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

    // MARK: - VPS Monitor

    func getVpsInstances(baseURL: String, page: Int = 0, size: Int = 1000) async throws -> InstanceListResponse {
        let url = try makeURL("\(baseURL)/oci/list/json", params: ["page": "\(page)", "size": "\(size)"])
        return try await get(url)
    }

    func pingInstances(baseURL: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/vps/instances/ping"), body: [:])
    }

    func enablePing(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/vps/instances/enablePing"), body: ["instanceId": instanceId])
    }

    func disablePing(baseURL: String, instanceId: String) async throws -> ActionResponse {
        return try await post(try makeURL("\(baseURL)/vps/instances/disablePing"), body: ["instanceId": instanceId])
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
        return try await post(try makeURL("\(baseURL)/api/system/updatePassword"), body: [
            "oldPassword": oldPassword,
            "newPassword": newPassword
        ])
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
        return try decode(data)
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
