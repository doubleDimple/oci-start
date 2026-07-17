import Foundation

/// Network layer for `/email/*` (+ enable via `/tenants/email/enable`, disabled list via `/tenants/list/json`).
struct EmailService {
    let baseURL: String
    private let client = APIClient.shared

    // MARK: - Enabled tenant configs

    /// Web: POST `/email/tenant/list` · pageNum 1-based
    func listEnabledConfigs(pageNum: Int, pageSize: Int) async throws -> EmailPageResult<TenantEmailConfigItem> {
        let url = try client.makeURL(baseURL, path: "/email/tenant/list")
        let raw = try await client.postJSON(url, body: [
            "pageNum": pageNum,
            "pageSize": pageSize,
            "sort": "createdTime",
            "order": "desc"
        ])
        let page = try EmailJSON.pageDict(raw)
        let meta = EmailJSON.parsePageMeta(page)
        let items = EmailJSON.contentArray(page).map { EmailJSON.parseConfig($0) }
        return EmailPageResult(
            content: items,
            totalElements: meta.total,
            totalPages: meta.pages,
            number: meta.number,
            size: meta.size
        )
    }

    /// Web: GET `/tenants/list/json?emailEnable=0`
    func listDisabledTenants(page: Int, size: Int, keyword: String?) async throws -> EmailPageResult<DisabledTenantItem> {
        var q: [String: String] = [
            "page": "\(page)",
            "size": "\(size)",
            "cloudType": "1",
            "emailEnable": "0"
        ]
        if let keyword = keyword, !keyword.isEmpty { q["keyword"] = keyword }
        let url = try client.makeURL(baseURL, path: "/tenants/list/json", query: q)
        let raw = try await client.getJSON(url)
        guard let root = EmailJSON.obj(raw) else {
            throw APIError.serverMessage("未开启租户列表解析失败")
        }
        let content = (root["content"] as? [[String: Any]]) ?? []
        let items = content.map { EmailJSON.parseDisabledTenant($0) }
        return EmailPageResult(
            content: items,
            totalElements: EmailJSON.int64(root["totalElements"]),
            totalPages: EmailJSON.int(root["totalPages"]),
            number: EmailJSON.int(root["currentPage"] ?? root["number"]),
            size: EmailJSON.int(root["size"])
        )
    }

    /// Web: POST `/tenants/email/enable`
    func enableEmail(tenantId: Int64, domain: String) async throws {
        let url = try client.makeURL(baseURL, path: "/tenants/email/enable")
        let raw = try await client.postJSON(url, body: [
            "tenantId": tenantId,
            "emailDomain": domain
        ])
        try EmailJSON.ensureSuccess(raw, fallback: "开启邮件服务失败")
    }

    /// Web: POST `/email/disable` body `{ id: configId }`
    func disableEmail(configId: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/email/disable")
        let raw = try await client.postJSON(url, body: ["id": configId])
        try EmailJSON.ensureSuccess(raw, fallback: "禁用邮件服务失败")
    }

    // MARK: - Contacts

    /// Web: POST `/email/receive/list`
    func listContacts(pageNum: Int, pageSize: Int) async throws -> EmailPageResult<EmailContactItem> {
        let url = try client.makeURL(baseURL, path: "/email/receive/list")
        let raw = try await client.postJSON(url, body: [
            "pageNum": pageNum,
            "pageSize": pageSize,
            "sort": "createTime",
            "order": "desc"
        ])
        let page = try EmailJSON.pageDict(raw)
        let meta = EmailJSON.parsePageMeta(page)
        let items = EmailJSON.contentArray(page).map { EmailJSON.parseContact($0) }
        return EmailPageResult(
            content: items,
            totalElements: meta.total,
            totalPages: meta.pages,
            number: meta.number,
            size: meta.size
        )
    }

    /// Web: POST `/email/receive/add`
    func addContact(name: String, email: String) async throws {
        let url = try client.makeURL(baseURL, path: "/email/receive/add")
        let raw = try await client.postJSON(url, body: ["name": name, "email": email])
        try EmailJSON.ensureSuccess(raw, fallback: "添加收件人失败")
    }

    /// Web: POST `/email/receive/delete?id=`
    func deleteContact(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/email/receive/delete", query: ["id": "\(id)"])
        let raw = try await client.postJSON(url, body: [:])
        try EmailJSON.ensureSuccess(raw, fallback: "删除收件人失败")
    }

    // MARK: - Send

    /// Web: POST `/email/send`
    func sendEmail(title: String, content: String, tenantEmailConfigId: Int64, receiveIds: [Int64]) async throws {
        let url = try client.makeURL(baseURL, path: "/email/send")
        let raw = try await client.postJSON(url, body: [
            "title": title,
            "content": content,
            "tenantEmailConfigId": tenantEmailConfigId,
            "emailReceiveIds": receiveIds
        ])
        try EmailJSON.ensureSuccess(raw, fallback: "发送邮件失败")
    }

    // MARK: - Records

    /// Web: POST `/email/body/list`
    func listBodies(pageNum: Int, pageSize: Int) async throws -> EmailPageResult<EmailBodyItem> {
        let url = try client.makeURL(baseURL, path: "/email/body/list")
        let raw = try await client.postJSON(url, body: [
            "pageNum": pageNum,
            "pageSize": pageSize,
            "sort": "createTime",
            "order": "desc"
        ])
        let page = try EmailJSON.pageDict(raw)
        let meta = EmailJSON.parsePageMeta(page)
        let items = EmailJSON.contentArray(page).map { EmailJSON.parseBody($0) }
        return EmailPageResult(
            content: items,
            totalElements: meta.total,
            totalPages: meta.pages,
            number: meta.number,
            size: meta.size
        )
    }

    /// Web: POST `/email/send/list`
    func listSendRecords(emailBodyId: String, pageNum: Int, pageSize: Int) async throws -> EmailPageResult<EmailSendRecordItem> {
        let url = try client.makeURL(baseURL, path: "/email/send/list")
        let raw = try await client.postJSON(url, body: [
            "emailBodyId": emailBodyId,
            "pageNum": pageNum,
            "pageSize": pageSize,
            "sort": "createTime",
            "order": "desc"
        ])
        let page = try EmailJSON.pageDict(raw)
        let meta = EmailJSON.parsePageMeta(page)
        let items = EmailJSON.contentArray(page).map { EmailJSON.parseSendRecord($0) }
        return EmailPageResult(
            content: items,
            totalElements: meta.total,
            totalPages: meta.pages,
            number: meta.number,
            size: meta.size
        )
    }

    /// Web: POST `/email/body/delete` body `{ id }`
    func deleteBody(id: Int64) async throws {
        let url = try client.makeURL(baseURL, path: "/email/body/delete")
        let raw = try await client.postJSON(url, body: ["id": id])
        try EmailJSON.ensureSuccess(raw, fallback: "删除记录失败")
    }

    /// Web: POST `/email/body/batchDelete`
    func batchDeleteBodies() async throws {
        let url = try client.makeURL(baseURL, path: "/email/body/batchDelete")
        let raw = try await client.postJSON(url, body: [:])
        try EmailJSON.ensureSuccess(raw, fallback: "批量删除失败")
    }
}
