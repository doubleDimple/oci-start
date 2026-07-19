import Foundation

/// Thin HTTP client: Cookie session, form/JSON helpers. No UI.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// 长耗时接口（如 `/tenants/syncOci`，Web 侧约 3 分钟进度窗口）
    private let longSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        let longConfig = URLSessionConfiguration.default
        longConfig.httpCookieStorage = HTTPCookieStorage.shared
        longConfig.httpShouldSetCookies = true
        longConfig.httpCookieAcceptPolicy = .always
        longConfig.timeoutIntervalForRequest = 200
        longConfig.timeoutIntervalForResource = 210
        longSession = URLSession(configuration: longConfig)
    }

    // MARK: - Raw

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request, using: session)
    }

    private func data(for request: URLRequest, using session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.compatData(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func getHTML(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, http) = try await data(for: req)
        guard (200..<400).contains(http.statusCode) else {
            throw APIError.serverMessage("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func getJSON(_ url: URL) async throws -> Data {
        try await getJSON(url, headers: [:])
    }

    func getJSON(_ url: URL, headers: [String: String]) async throws -> Data {
        try await getJSON(url, headers: headers, longTimeout: false)
    }

    /// - Parameter longTimeout: 使用长会话（约 200s），给同步类接口用。
    func getJSON(
        _ url: URL,
        headers: [String: String] = [:],
        longTimeout: Bool
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if longTimeout {
            req.timeoutInterval = 200
        }
        let sess = longTimeout ? longSession : session
        let (data, http) = try await data(for: req, using: sess)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage(Self.friendlyServerMessage(data: data, status: http.statusCode))
        }
        return data
    }

    /// 尽量从 JSON body 抽出可读错误（如 syncOci `{"status":"error","message":"..."}`）
    private static func friendlyServerMessage(data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["message"] as? String, !msg.isEmpty { return msg }
            if let msg = obj["msg"] as? String, !msg.isEmpty { return msg }
            if let err = obj["error"] as? String, !err.isEmpty { return err }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty, raw.count < 240 { return raw }
        return "HTTP \(status)"
    }

    /// Binary / export download (returns body + suggested filename).
    func download(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, String?) {
        let result = try await downloadWithHeaders(url, headers: headers)
        return (result.data, result.filename)
    }

    /// Binary download with response header map (e.g. migration `X-MASTER-KEY`).
    func downloadWithHeaders(
        _ url: URL,
        headers: [String: String] = [:]
    ) async throws -> (data: Data, filename: String?, headers: [AnyHashable: Any]) {
        var req = URLRequest(url: url)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.serverMessage(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)
        }
        var name: String?
        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let r = cd.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
                name = String(cd[r]).replacingOccurrences(of: "filename=\"", with: "").replacingOccurrences(of: "\"", with: "")
            } else if let r = cd.range(of: "filename=([^;]+)", options: .regularExpression) {
                name = String(cd[r]).replacingOccurrences(of: "filename=", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (data, name, http.allHeaderFields)
    }

    func putJSON(_ url: URL, body: [String: Any]? = [:]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            req.httpBody = Data("{}".utf8)
        }
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.serverMessage(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)
        }
        return data
    }

    func deleteJSON(_ url: URL, body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body = body {
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.serverMessage(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)
        }
        return data
    }

    func postForm(_ url: URL, fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = formBody(fields)
        return try await data(for: req)
    }

    /// JSON POST body (empty `{}` when body is nil).
    func postJSON(_ url: URL, body: [String: Any]? = [:]) async throws -> Data {
        try await postJSON(url, body: body, longTimeout: false)
    }

    /// - Parameter longTimeout: 使用长会话（约 200s），给安装/同步类接口用。
    func postJSON(_ url: URL, body: [String: Any]? = [:], longTimeout: Bool) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if longTimeout {
            req.timeoutInterval = 200
        }
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            req.httpBody = Data("{}".utf8)
        }
        let sess = longTimeout ? longSession : session
        let (data, http) = try await data(for: req, using: sess)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage(Self.friendlyServerMessage(data: data, status: http.statusCode))
        }
        return data
    }

    /// multipart/form-data POST (e.g. `/tenants/save` with `keyFileStr`).
    func postMultipart(
        _ url: URL,
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = body
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.serverMessage(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)
        }
        return data
    }

    // MARK: - Auth endpoints

    func fetchLoginPage(baseURL: String) async throws -> String {
        let url = try makeURL(baseURL, path: "/login")
        return try await getHTML(url)
    }

    struct LoginResult: Decodable {
        let success: Bool?
        let redirectUrl: String?
        let message: String?
    }

    func performLogin(
        baseURL: String,
        username: String,
        password: String,
        verificationCode: String?,
        mfaCode: String?,
        rememberMe: Bool = true
    ) async throws -> LoginResult {
        let url = try makeURL(baseURL, path: "/perform_login")
        var fields = [
            "username": username,
            "password": password,
            "remember-me": rememberMe ? "true" : "false"
        ]
        if let code = verificationCode, !code.isEmpty {
            fields["verificationCode"] = code
        }
        if let code = mfaCode, !code.isEmpty {
            fields["mfaCode"] = code
        }

        do {
            let (data, http) = try await postForm(url, fields: fields)
            if http.statusCode == 401 {
                let partial = try? JSONDecoder().decode(LoginResult.self, from: data)
                throw APIError.serverMessage(partial?.message ?? "用户名或密码错误")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.serverMessage("登录失败 HTTP \(http.statusCode)")
            }
            if data.isEmpty {
                return LoginResult(success: true, redirectUrl: nil, message: nil)
            }
            return try JSONDecoder().decode(LoginResult.self, from: data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    /// Parse flags from `/login` HTML (same source as Web page).
    struct LoginPageMeta {
        var allowRegister: Bool
        var githubEnabled: Bool
        var googleEnabled: Bool
        var publicKey: String?
    }

    func fetchLoginPageMeta(baseURL: String) async throws -> LoginPageMeta {
        let html = try await fetchLoginPage(baseURL: baseURL)
        let allow = html.contains("id=\"registerForm\"") || html.contains("switchTab('register')")
        let githubOn = html.contains("id=\"githubLoginBtn\"")
        let googleOn = html.contains("id=\"googleLoginBtn\"")
        return LoginPageMeta(
            allowRegister: allow,
            githubEnabled: githubOn,
            googleEnabled: googleOn,
            publicKey: nil
        )
    }

    func sendLoginVerificationCode(baseURL: String, username: String) async throws {
        let url = try makeURL(baseURL, path: "/api/send-verification-code")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let body = ["username": username]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "发送失败"
            throw APIError.serverMessage(msg)
        }
    }

    func registerFirstUser(baseURL: String, username: String, password: String) async throws {
        let url = try makeURL(baseURL, path: "/api/register-first-user")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let body = ["username": username, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await data(for: req)
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "注册失败"
            throw APIError.serverMessage(msg)
        }
    }

    func oauthLoginURL(baseURL: String, provider: String) async throws -> URL {
        // provider: github | google
        let path = provider == "google" ? "/api/google/login/url" : "/api/github/login/url"
        let url = try makeURL(baseURL, path: path)
        let data = try await getJSON(url)
        // may be plain string URL or JSON
        if let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r")) ,
           let u = URL(string: s), u.scheme != nil {
            return u
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["url"] as? String, let u = URL(string: s) { return u }
            if let s = obj["data"] as? String, let u = URL(string: s) { return u }
        }
        throw APIError.serverMessage("无法获取 \(provider) 登录地址")
    }

    func performLogout(baseURL: String) async {
        guard let url = try? makeURL(baseURL, path: "/perform_logout") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try? await session.compatData(for: req)
        clearCookies(for: baseURL)
    }

    /// True only if a non-empty `satoken` cookie exists for this host.
    func hasSaTokenCookie(baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host,
              let cookies = HTTPCookieStorage.shared.cookies else { return false }
        for c in cookies {
            let domainOK = c.domain.contains(host) || host.contains(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            if domainOK && (c.name == "satoken" || c.name.lowercased().contains("satoken")) {
                return !c.value.isEmpty
            }
        }
        // Also accept localhost / 127.0.0.1 crossover
        for c in cookies where c.name == "satoken" && !c.value.isEmpty {
            if c.domain.contains("localhost") || c.domain.contains("127.0.0.1") || host == "localhost" || host == "127.0.0.1" {
                return true
            }
        }
        return false
    }

    /// Strict session probe: must have satoken cookie AND authenticated JSON API.
    func validateSession(baseURL: String) async -> Bool {
        guard hasSaTokenCookie(baseURL: baseURL) else { return false }
        guard let url = try? makeURL(baseURL, path: "/oci/list/json", query: ["page": "0", "size": "1"]) else {
            return false
        }
        do {
            let data = try await getJSON(url)
            // Reject HTML login pages accidentally returned as 200
            if let s = String(data: data.prefix(32), encoding: .utf8),
               s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                return false
            }
            // Prefer JSON object/array
            let obj = try? JSONSerialization.jsonObject(with: data)
            return obj != nil
        } catch {
            return false
        }
    }

    struct LoginFactorConfig {
        var messageEnabled: Bool
        var mfaEnabled: Bool
    }

    func fetchLoginFactorConfig(baseURL: String) async -> LoginFactorConfig {
        async let msg = fetchBool(baseURL, path: "/api/config/message-enabled")
        async let mfa = fetchBool(baseURL, path: "/api/config/mfa-enabled")
        return await LoginFactorConfig(messageEnabled: msg, mfaEnabled: mfa)
    }

    // MARK: - Forgot password (web login_user_v1.js)

    func sendResetCode(baseURL: String, username: String) async throws {
        let url = try makeURL(baseURL, path: "/api/send-reset-code")
        let data = try await postJSON(url, body: ["username": username])
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = obj["success"] as? Bool, success == false {
            throw APIError.serverMessage((obj["message"] as? String) ?? "发送失败")
        }
    }

    /// Returns resetToken on success.
    func verifyResetCode(baseURL: String, username: String, verificationCode: String) async throws -> String {
        let url = try makeURL(baseURL, path: "/api/verify-reset-code")
        let data = try await postJSON(url, body: [
            "username": username,
            "verificationCode": verificationCode
        ])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverMessage("验证失败")
        }
        let success = (obj["success"] as? Bool) ?? false
        guard success else {
            throw APIError.serverMessage((obj["message"] as? String) ?? "验证失败")
        }
        if let dataObj = obj["data"] as? [String: Any],
           let token = dataObj["resetToken"] as? String, !token.isEmpty {
            return token
        }
        if let token = obj["resetToken"] as? String, !token.isEmpty {
            return token
        }
        throw APIError.serverMessage((obj["message"] as? String) ?? "未返回重置令牌")
    }

    func resetPassword(baseURL: String, username: String, resetToken: String) async throws -> String {
        let url = try makeURL(baseURL, path: "/api/reset-password")
        let data = try await postJSON(url, body: [
            "username": username,
            "resetToken": resetToken
        ])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverMessage("重置失败")
        }
        let success = (obj["success"] as? Bool) ?? false
        let message = (obj["message"] as? String) ?? (success ? "密码已重置" : "重置失败")
        guard success else { throw APIError.serverMessage(message) }
        return message
    }

    // MARK: - Helpers

    func clearCookies(for baseURL: String) {
        guard let host = URL(string: baseURL)?.host,
              let cookies = HTTPCookieStorage.shared.cookies else { return }
        for cookie in cookies where cookie.domain.contains(host) || host.contains(cookie.domain) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func fetchBool(_ baseURL: String, path: String) async -> Bool {
        guard let url = try? makeURL(baseURL, path: path) else { return false }
        do {
            let data = try await getJSON(url)
            return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
        } catch {
            return false
        }
    }

    private func formBody(_ fields: [String: String]) -> Data? {
        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery?.data(using: .utf8)
    }

    func makeURL(_ baseURL: String, path: String, query: [String: String] = [:]) throws -> URL {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard var comps = URLComponents(string: root + p) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.invalidURL }
        return url
    }
}
