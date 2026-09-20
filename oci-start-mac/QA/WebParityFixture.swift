import AppKit
import SwiftUI
import Foundation
import ObjectiveC
@testable import OciStart

setbuf(stdout, nil)

// Separate executable/preferences, with every URLSession request intercepted.
// Unknown URLs fail locally. This fixture never connects to a real backend.
let revision = String(repeating: "a", count: 64)
let tokenMetadata: [String: Any] = [
    "revision": revision, "tokenName": "开发工具", "description": "供本地自动化使用的访问令牌",
    "enabled": true, "hasToken": true, "isExpired": false, "expirationDays": 30,
    "createdAt": "2026-09-19T09:30:00", "expiresAt": "2026-10-19T09:30:00",
    "daysUntilExpiration": 30, "allowSwaggerAccess": true,
    "serverTime": 1789781400000 as Int64, "expiresAtEpochMs": 1792373400000 as Int64,
    "serverTimeZone": "Asia/Shanghai"
]
func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }
func success(_ payload: Any) -> String { json(["success": true, "code": 200, "data": payload]) }
let memoRows: [[String: Any]] = [
    ["id": 1, "title": "环境部署说明", "summary": "连接方式与服务维护", "content": "保留本地与远程登录。\n定期备份配置。", "htmlContent": "<h2>连接方式</h2><p>保留<strong>本地</strong>与<em>远程</em>登录。</p><ul><li>定期备份配置。</li><li>检查服务状态。</li></ul>", "createTime": "2026-09-18T09:30:00", "updateTime": "2026-09-19T10:00:00"],
    ["id": 2, "title": "区域资源记录", "summary": "东京与新加坡", "content": "当前区域资源情况。", "htmlContent": "<p>当前区域资源情况。</p>", "createTime": "2026-09-18T09:30:00", "updateTime": "2026-09-19T09:00:00"]
]
final class PreviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: String
        var status = 200
        fputs("Fixture request: \(path)\n", stderr)
        switch path {
        case "/perform_login": status = 401; body = json(["success": false, "message": "fixture password rejected"])
        case "/tenants/list/json": body = #"{"content":[{"id":1,"tenancyName":"Preview Tokyo","defName":"界面验收数据","region":"ap-tokyo-1","accountTypeName":"免费账户","activeDays":"128","createdAtStr":"2026-09-17","apiSynced":true},{"id":2,"tenancyName":"Preview Singapore","defName":"长名称在表格中保持对齐","region":"ap-singapore-1","accountTypeName":"付费账户","activeDays":"256","createdAtStr":"2026-09-17","apiSynced":true}],"currentPage":0,"totalPages":7,"totalElements":70,"size":10}"#
        case "/vpnProxy/pageList":
            // List rendering only: no connection test, save, delete or binding
            // endpoint is mocked, and all unknown requests fail locally.
            precondition(request.httpMethod == "POST")
            body = success(["content": [
                ["id": 1, "customName": "Tokyo production egress proxy with a long name", "proxyType": "HTTP", "proxyHost": "tokyo-proxy.fixture.invalid", "proxyPort": 8080, "proxyUsername": "preview-long-account-name", "proxyPassword": "", "tenantId": 1, "tenantName": "Preview Tokyo tenancy", "forceProxy": 0, "availableStatus": 1],
                ["id": 2, "customName": "Singapore global egress", "proxyType": "HTTPS", "proxyHost": "singapore-proxy.fixture.invalid", "proxyPort": 8443, "proxyUsername": "fixture", "proxyPassword": "", "tenantName": "", "forceProxy": 1, "availableStatus": 0]],
                "number": 0, "size": 10, "totalElements": 2, "totalPages": 1])
        case "/tenants/listParentTenants":
            body = success([["id": 1, "tenancyName": "Preview Tokyo", "region": "ap-tokyo-1"]])
        case "/api/system/apiTokenConfigs": body = json(["success": true, "data": tokenMetadata])
        case "/api/system/apiTokenMaterial":
            precondition(request.url?.query == "revision=" + revision)
            body = json(["success": true, "data": ["metadata": tokenMetadata, "tokenValue": "fixture-token-value"]])
        case "/api/system/generateApiToken":
            precondition(request.value(forHTTPHeaderField: "If-Match") == revision)
            precondition(request.httpMethod == "POST")
            if request.url?.host == "rejected.invalid" {
                status = 409
                body = json(["success": false, "errorKey": "conflict", "writeAttempted": false])
            } else if request.url?.host == "unknown.invalid" {
                body = json(["success": true, "data": [:]])
            } else { body = json(["success": true, "data": ["metadata": tokenMetadata, "tokenValue": "fixture-token-value"]]) }
        case "/api/memos": body = json(memoRows)
        case "/api/memos/1": body = json(["memo": memoRows[0], "revision": revision])
        case "/api/mfa/entries":
            body = json(["success": true, "data": [
                ["id": "1", "keyName": "开发账号", "issuer": "GitHub", "createTime": "2026-09-18 09:30:00", "revision": revision],
                ["id": "2", "keyName": "云平台", "issuer": "Oracle", "createTime": "2026-09-19 09:30:00", "revision": revision]]])
        case "/api/mfa/codes":
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            body = json(["success": true, "serverTime": now, "expiresAt": now + 25000, "items": [
                ["id": "1", "code": "123456"], ["id": "2", "code": "654321"]]])
        case "/resource/arm-data":
            body = success(["armRecords": [
                ["region": "ap-tokyo-1", "architectureType": "ARM", "openTime": "2026-09-19 09:30:00", "openCount": 12, "monthlyOpenCount": 78],
                ["region": "ap-singapore-1", "architectureType": "ARM", "openTime": "2026-09-18 12:00:00", "openCount": 7, "monthlyOpenCount": 28],
                ["region": "eu-frankfurt-1", "architectureType": "ARM", "openCount": 9, "monthlyOpenCount": 19]],
                "regionMap": ["ap-tokyo-1": "东京", "ap-singapore-1": "新加坡", "eu-frankfurt-1": "法兰克福"]])
        case "/resource/my-regions":
            body = success(["hasRecords": [["region": "ap-tokyo-1"], ["region": "us-ashburn-1"]]])
        case "/api/audit-logs":
            body = json(["success": true, "code": 200, "data": ["content": [
                ["id": 1, "username": "Preview", "title": "查看区域", "method": "GET", "requestUri": "/resource/arm-data", "ip": "127.0.0.1", "location": "本地", "responseStatus": 200, "status": 1, "costTime": 35, "createTime": "2026-09-19T09:30:00"],
                ["id": 2, "username": "Preview", "title": "读取备份", "method": "GET", "requestUri": "/api/memos", "ip": "127.0.0.1", "location": "本地", "responseStatus": 500, "status": 0, "costTime": 18, "errorMsg": "模拟读取失败", "createTime": "2026-09-19T09:20:00"]],
                "totalElements": 2, "totalPages": 1]])
        case "/api/system/securitySettingsConfigs":
            precondition(request.url?.query == "redacted=true")
            body = json(["success": true, "data": [
                "currentUsername": "Preview", "siteLogoName": "OCI-START", "channelNotifyEnabled": false,
                "github": ["enabled": false, "hasClientSecret": true],
                "google": ["enabled": false, "hasClientSecret": false],
                "mfa": ["enabled": true, "hasSecretKey": true, "issuer": "OCI-START"],
                "turnstile": ["enabled": false, "hasSecretKey": false]]])
        case "/api/system/notifyConfigs":
            precondition(request.url?.query == "redacted=true")
            body = json(["success": true, "data": [
                "serverTimeZone": "Asia/Shanghai",
                "task": ["enabled": true, "executeHour": 9, "hasNotificationSecret": true, "enableAccountCheck": true, "enableBootLog": true, "enableCostCheck": false],
                "telegram": ["enabled": true, "hasBotToken": true, "chatId": "123456", "chatName": "运维通知"],
                "proxy": ["enabled": false, "type": "HTTP", "host": "127.0.0.1", "port": 7890, "hasPassword": false],
                "bark": ["enabled": false, "hasDeviceKey": false],
                "dingTalk": ["enabled": false, "hasWebhook": false, "hasSecret": false],
                "feishu": ["enabled": false, "hasWebhook": false, "hasSecret": false]]])
        case "/api/userInfo": body = #"{"success":true,"data":{"username":"Preview"}}"#
        case "/sysMessage/countUnread": body = #"{"success":true,"data":0}"#
        default:
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}


extension URLSessionConfiguration {
    @objc class func previewConfiguration() -> URLSessionConfiguration {
        let config = previewConfiguration()
        config.protocolClasses = [PreviewProtocol.self]
        config.urlCache = nil
        config.httpCookieStorage = nil
        return config
    }
}
let originalFactory = class_getClassMethod(URLSessionConfiguration.self, NSSelectorFromString("defaultSessionConfiguration"))!
let previewFactory = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.previewConfiguration))!
method_exchangeImplementations(originalFactory, previewFactory)

UserDefaults.standard.setVolatileDomain([
    "appAppearance": "light", "deploymentMode": "remote", "deploymentModeChosen": false,
    "serverURL": "https://oci-mac-preview.invalid", "remoteServerURL": "https://oci-mac-preview.invalid",
    "lastUsername": "Preview", "cloudProvider": 1, "sidebarCollapsed": false,
    "appLocale": "zh_CN"
], forName: UserDefaults.argumentDomain)
URLProtocol.registerClass(PreviewProtocol.self)
Task { @MainActor in fputs("MainActor preview task reached\n", stderr) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appearance = AppearanceController.shared
let session = AppSession.shared
let navigation = NavigationState.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let fixtureOriginalWindowLevel = window.level
window.level = .floating
let shell = MainShellViewController(session: session, navigation: navigation, appearance: appearance)
let container = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
window.contentView = container
shell.view.frame = container.bounds
shell.view.autoresizingMask = [.width, .height]
container.addSubview(shell.view)
window.orderFront(nil)
app.activate(ignoringOtherApps: true)

let output = ProcessInfo.processInfo.environment["OCI_CAPTURE_DIR"] ?? "/private/tmp/oci-mac-web-qa/shots"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let allScenarios: [(String, NavID, Bool, Bool, CGFloat)] = [
    ("tenants-light", .tenants, false, false, 1280),
    ("tenants-dark", .tenants, true, false, 1280),
    ("tenants-narrow", .tenants, false, false, 960),
    ("proxy-narrow", .proxyConfig, false, false, 960),
    ("settings-light", .settings, false, false, 1280),
    ("dashboard-light", .dashboard, false, false, 1280),
    ("instances-compact", .instances, false, true, 960),
    ("regions-light", .regions, false, false, 1280),
    ("regions-dark", .regions, true, false, 1280),
    ("regions-narrow", .regions, false, true, 960),
    ("regions-english-narrow", .regions, false, false, 960),
    ("memo-light", .memo, false, false, 1280),
    ("memo-dark", .memo, true, false, 1280),
    ("mfa-light", .mfa, false, false, 1280),
    ("mfa-narrow", .mfa, true, true, 960),
    ("audit-light", .auditLogs, false, false, 1280),
    ("notify-light", .notify, false, false, 1280),
    ("tokens-light", .apiTokens, false, false, 1280),
    ("tokens-dark", .apiTokens, true, false, 1280),
    ("migration-light", .migration, false, false, 1280),
    ("resources-unavailable", .vpsList, false, true, 960)
]
// Optional bounded rerun after a layout-only edit; all HTTP remains intercepted.
let layoutOnly = ProcessInfo.processInfo.environment["OCI_LAYOUT_QA_ONLY"] == "1"
let scenarios = layoutOnly ? allScenarios.filter {
    ["tenants-narrow", "proxy-narrow", "regions-english-narrow"].contains($0.0)
} : allScenarios
var index = 0
var validationFailures: [String] = []
func snapshot(_ name: String) {
    container.layoutSubtreeIfNeeded()
    container.displayIfNeeded()
    guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { fatalError("No bitmap") }
    container.cacheDisplay(in: container.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
    try! data.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
    print("Captured \(name) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
}
func next() {
    guard index < scenarios.count else {
        tableFixtureTrace("all list scenarios complete; removing shell before login")
        shell.view.removeFromSuperview()
        tableFixtureTrace("shell removed; creating login hosting view")
        let login = NSHostingView(rootView: LoginView().environmentObject(session).environmentObject(BackendController.shared).environmentObject(appearance))
        tableFixtureTrace("login hosting view created; resizing window")
        window.setContentSize(NSSize(width: 1280, height: 800))
        login.frame = container.bounds
        login.autoresizingMask = [.width, .height]
        container.addSubview(login)
        tableFixtureTrace("login hosting view mounted")
        appearance.mode = .light
        tableFixtureTrace("login light appearance applied; scheduling verification after 2 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            tableFixtureTrace("login verification dispatch deadline reached; entering main callback verification")
            verifyLoginGlobeAnimation(in: container, capture: snapshot) { result in
                if case .failure(let error) = result {
                    let failure = "login globe animation: \(error.localizedDescription)"
                    validationFailures.append(failure)
                    fputs("FAIL: \(failure)\n", stderr)
                }
                tableFixtureTrace("login globe completion callback; capturing light")
                snapshot("login-light")
                appearance.mode = .dark
                tableFixtureTrace("login dark appearance applied; scheduling capture")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    tableFixtureTrace("login dark capture deadline reached")
                    snapshot("login-dark")
                    login.removeFromSuperview()
                    tableFixtureTrace("login host removed after captures")
                    if layoutOnly { finishFixture() } else { captureForm(0) }
                }
            }
        }
        return
    }
    let scenario = scenarios[index]
    var preferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    preferences["appLocale"] = scenario.0.contains("english") ? "en_US" : "zh_CN"
    UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
    appearance.mode = scenario.2 ? .dark : .light
    navigation.sidebarCollapsed = scenario.3
    window.setContentSize(NSSize(width: scenario.4, height: scenario.4 == 960 ? 640 : 800))
    navigation.select(scenario.1)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        Task { @MainActor in
            if scenario.0 == "tenants-narrow" {
                do { try await verifyTenantFixedActions(in: container) }
                catch {
                    let failure = "fixed table actions: \(error.localizedDescription)"
                    validationFailures.append(failure)
                    fputs("FAIL: \(failure)\n", stderr)
                }
            }
            if scenario.0 == "proxy-narrow" || scenario.0 == "regions-english-narrow" {
                let proxy = scenario.0 == "proxy-narrow"
                do {
                    try await verifyBusinessTable(in: container, name: scenario.0,
                        firstHeader: proxy ? "名称" : "Region", lastHeader: proxy ? "操作" : "Last report",
                        headers: proxy ? ["名称", "类型", "地址", "端口", "用户名", "密码", "租户", "强制", "连通状态", "操作"]
                            : ["Region", "Status", "Architecture", "Launches", "This month", "First launch", "Last report"],
                        capture: { snapshot(scenario.0 + "-last-column") })
                } catch {
                    let failure = "\(scenario.0) table layout: \(error.localizedDescription)"
                    validationFailures.append(failure)
                    fputs("FAIL: \(failure)\n", stderr)
                }
            }
            snapshot(scenario.0)
            index += 1
            next()
        }
    }
}

struct PreviewLogin: View {
    @ObservedObject var model: LoginFormModel
    @ObservedObject var appearance: AppearanceController
    var body: some View {
        let dark = appearance.isShellDark
        ZStack {
            HStack(spacing: 0) {
                LoginHeroView(dark: dark, locale: model.locale).frame(maxWidth: .infinity)
                LoginRightPanel(model: model, dark: dark, backend: BackendController.shared,
                    onLogin: {}, onRegister: {}, onSendCode: {}, onOAuth: { _ in })
                    .frame(width: 486)
            }
            if model.showForgotPassword {
                LoginForgotPasswordSheet(model: model, dark: dark, onClose: {}, onSendCode: {}, onNext: {}, onBack: {})
            }
        }.environmentObject(appearance)
    }
}
let formModel = LoginFormModel()
var formHost: NSHostingView<PreviewLogin>?
func finishFixture() {
    window.level = fixtureOriginalWindowLevel
    print("PASS: native fixture captures finished")
    if !validationFailures.isEmpty { print("FAIL: \(validationFailures.count) validation check(s) failed") }
    exit(validationFailures.isEmpty ? 0 : 1)
}
func captureForm(_ step: Int) {
    guard step < 6 else {
        finishFixture()
        return
    }
    if step == 0 {
        formModel.modeActivated = true
        formModel.deploymentMode = .remote
        formModel.hasPersistedChoice = true
        formModel.serverURL = "https://oci-mac-preview.invalid"
        formModel.metaLoadedURL = formModel.serverURL
        formModel.allowRegister = true
        formModel.githubEnabled = true
        formModel.googleEnabled = true
        formModel.username = "preview"
        formModel.messageEnabled = true
        formModel.mfaEnabled = true
        let host = NSHostingView(rootView: PreviewLogin(model: formModel, appearance: appearance))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        formHost = host
    }
    let names = ["login-form-light", "login-form-dark-mfa", "register-english", "reset-light", "reset-dark", "login-local-waiting"]
    appearance.mode = step == 1 || step == 4 ? .dark : .light
    formModel.locale = step == 2 ? .enUS : .zhCN
    formModel.tab = step == 2 ? .register : .login
    formModel.verifyMethod = step == 1 ? .mfa : .message
    formModel.showForgotPassword = step == 3 || step == 4
    formModel.deploymentMode = step == 5 ? .local : .remote
    formModel.serverURL = step == 5 ? AppSession.localDefaultURL : "https://oci-mac-preview.invalid"
    formModel.resetStep = step == 4 ? 2 : 1
    if step == 2 { window.setContentSize(NSSize(width: 960, height: 640)) }
    else { window.setContentSize(NSSize(width: 1280, height: 800)) }
    func resetFormScroll(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           scroll.convert(scroll.bounds, to: container).midX > container.bounds.width * 0.55 {
            let top = document.isFlipped ? 0 : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        view.subviews.forEach(resetFormScroll)
    }
    resetFormScroll(container)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        snapshot(names[step])
        if step <= 2 {
            func scrollForms(_ view: NSView) {
                if let scroll = view as? NSScrollView, let document = scroll.documentView {
                    let position = scroll.convert(scroll.bounds, to: container)
                    if position.midX > container.bounds.width * 0.55 {
                        let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? bottom : 0))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
                view.subviews.forEach(scrollForms)
            }
            scrollForms(container)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                snapshot(names[step] + "-bottom")
                captureForm(step + 1)
            }
        } else { captureForm(step + 1) }
    }
}

@MainActor
func verifyContracts() async throws {
    precondition(AppSession.normalize("https://") == "https://")
    precondition(AppSession.normalize("https:") == "https://")
    precondition(AppSession.normalize("https://example.invalid/tenants") == "https://example.invalid")
    let login = LoginFormModel()
    precondition(!login.modeActivated && !login.canAttemptLogin(backendReady: true))
    login.modeActivated = true; login.deploymentMode = .remote
    precondition(login.isRemoteServer && login.canAttemptLogin(backendReady: true))
    login.deploymentMode = .local
    precondition(login.isLocalActivated && !login.canAttemptLogin(backendReady: false))
    do {
        _ = try await APIClient.shared.performLogin(baseURL: "https://oci-mac-preview.invalid", username: "Fixture", password: "Fixture", verificationCode: nil, mfaCode: nil)
        fatalError("Invalid password accepted")
    } catch APIError.serverMessage(let message) { precondition(message == "fixture password rejected") }
    let parsed = try ApiTokensJSON.state(tokenMetadata)
    precondition(parsed.hasToken && parsed.form.expirationDays == 30)
    do { _ = try ApiTokensJSON.state([:]); fatalError("Incomplete metadata accepted") }
    catch is ApiTokenFailure {}
    let token = try await ApiTokensService(baseURL: "https://oci-mac-preview.invalid").material(revision: revision)
    precondition(token.metadata.revision == revision && !token.tokenValue.isEmpty)
    let form = ApiTokenForm(tokenName: "Fixture", expirationDays: 7, description: "")
    _ = try await ApiTokensService(baseURL: "https://oci-mac-preview.invalid").generate(form, revision: revision)
    do { _ = try await ApiTokensService(baseURL: "https://rejected.invalid").generate(form, revision: revision); fatalError("Conflict accepted") }
    catch let error as ApiTokenFailure { precondition(!error.writeAttempted && error.key == "conflict") }
    do { _ = try await ApiTokensService(baseURL: "https://unknown.invalid").generate(form, revision: revision); fatalError("Missing receipt accepted") }
    catch let error as ApiTokenFailure { precondition(error.writeAttempted) }
    let memo = try await MemoService(baseURL: "https://oci-mac-preview.invalid").get(id: 1)
    precondition(memo.revision == revision && memo.htmlContent?.contains("<strong>") == true)
    let mfa = try await MfaBackupService(baseURL: "https://oci-mac-preview.invalid").listKeys()
    precondition(mfa.count == 2 && mfa[0].revision == revision)
    let regions = RegionsViewModel()
    await regions.refresh()
    precondition(regions.armLoaded && regions.mineLoaded && regions.sharedCount == 1)
    let codes = try await MfaBackupService(baseURL: "https://oci-mac-preview.invalid").codes(ids: mfa.map(\.id))
    precondition(codes.codes.count == 2 && codes.validFor > 0 && codes.validFor <= 25)
    let goodReceipt = json(["success": true, "formatVersion": 2, "importedRows": 2, "preservedRows": 1,
                           "tables": [["table": "tenant", "importedRows": 2, "preservedRows": 1]]])
    let receipt = try MigrationJSON.parseReceipt(Data(goodReceipt.utf8), status: 200)
    precondition(receipt.importedRows == 2 && receipt.preservedRows == 1)
    do { _ = try MigrationJSON.parseReceipt(Data("{\"success\":true}".utf8), status: 200); fatalError("Incomplete migration receipt accepted") }
    catch let error as MigrationFailure { precondition(error.outcome == .unknown) }
    print("PASS: login mode gates, token conditional writes and unknown receipts, guarded note HTML, region intersection, MFA expiry, migration receipts")
    for check in try consoleOfflineChecks() { print("PASS: console: \(check)") }
    for check in try await TerminalFixture.run() { print("PASS: \(check)") }
}
Task { @MainActor in
    // The standalone table fixture owns the screen while it runs. Keep the
    // shell's separate floating window from obscuring synthetic-event targets.
    window.orderOut(nil)
    do { try await verifySharedTableLayout(captureDirectory: output) }
    catch {
        let failure = "shared table layout: \(error.localizedDescription)"
        validationFailures.append(failure)
        fputs("FAIL: \(failure)\n", stderr)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    do { if !layoutOnly { try await verifyContracts() } }
    catch {
        let failure = "fixture contract check: \(error)"
        validationFailures.append(failure)
        fputs("FAIL: \(failure)\n", stderr)
    }
    next()
}
app.run()
