import Foundation
import Combine
import AppKit

/// Header chrome APIs: userInfo, messages, version, asset analysis.
@MainActor
final class HeaderViewModel: ObservableObject {
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var messagePage = SysMessagePage()
    @Published private(set) var messagesLoading = false
    @Published private(set) var version = VersionCheckInfo()
    @Published private(set) var levelBadgeTitle: String = "Lvl.1"
    @Published private(set) var levelBadgeLevel: Int = 1
    @Published var locale: AppLocale = .zhCN
    @Published var showMessages = false
    @Published var showAsset = false
    @Published var showAbout = false
    @Published var showUpdateProgress = false
    @Published var updatePhase: VersionUpdatePhase = .idle
    @Published var selectedMessage: SysMessageItem?
    @Published var messageDetail: SysMessageItem?
    @Published var asset: AssetAnalysis?
    @Published var assetLoading = false
    @Published var assetError: String?

    private let session: AppSession
    private var pollTimer: Timer?
    private let localeKey = "appLocale"

    init(session: AppSession = .shared) {
        self.session = session
        if let raw = UserDefaults.standard.string(forKey: localeKey),
           let loc = AppLocale(rawValue: raw) {
            locale = loc
        }
    }

    func start() {
        Task {
            await refreshUserInfo()
            await refreshUnread()
            await checkVersion()
        }
        stopPoll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshUnread()
                await self.checkVersion()
            }
        }
        if let pollTimer = pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func stop() {
        stopPoll()
    }

    func setLocale(_ loc: AppLocale) {
        locale = loc
        UserDefaults.standard.set(loc.rawValue, forKey: localeKey)
        // Instant — no text toast; selection checkmark is enough.
    }

    // MARK: - User

    func refreshUserInfo() async {
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/api/userInfo")
            let raw = try await APIClient.shared.getJSON(url)
            if let env = try? JSONDecoder().decode(APIEnvelope<[String: String]>.self, from: raw),
               env.success, let name = env.data?["username"], !name.isEmpty {
                session.applyRemoteUsername(name)
            } else if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let data = obj["data"] as? [String: Any],
                      let name = data["username"] as? String {
                session.applyRemoteUsername(name)
            }
        } catch {
            // keep local username
        }
    }

    // MARK: - Messages

    func refreshUnread() async {
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/countUnread")
            let raw = try await APIClient.shared.postJSON(url, body: [:])
            if let env = try? JSONDecoder().decode(APIEnvelope<Int>.self, from: raw), env.success {
                unreadCount = env.data ?? 0
            } else if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let success = obj["success"] as? Bool, success {
                if let n = obj["data"] as? Int {
                    unreadCount = n
                } else if let n = obj["data"] as? Int64 {
                    unreadCount = Int(n)
                }
            }
        } catch {
            // ignore poll errors
        }
    }

    func openMessages() {
        messageDetail = nil
        selectedMessage = nil
        showMessages = true
        Task { await loadMessages(page: 1) }
    }

    func closeMessages() {
        showMessages = false
        messageDetail = nil
        selectedMessage = nil
    }

    func toggleMessages() {
        if showMessages {
            closeMessages()
        } else {
            openMessages()
        }
    }

    /// 详情 → 列表
    func backToMessageList() {
        messageDetail = nil
        selectedMessage = nil
    }

    func loadMessages(page: Int) async {
        messagesLoading = true
        defer { messagesLoading = false }
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/list")
            let raw = try await APIClient.shared.postJSON(url, body: [
                "pageNum": page,
                "pageSize": 12
            ])
            messagePage = parseMessagePage(raw, pageNum: page)
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func markAllRead() async {
        await LoadingHUD.shared.during {
            do {
                let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/read")
                _ = try await APIClient.shared.postJSON(url, body: [:])
                await loadMessages(page: messagePage.pageNum)
                await refreshUnread()
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    func deleteMessage(_ id: String) async {
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/del")
            _ = try await APIClient.shared.postJSON(url, body: ["businessId": id])
            await loadMessages(page: messagePage.pageNum)
            await refreshUnread()
        } catch {
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    func openMessageDetail(_ item: SysMessageItem) async {
        selectedMessage = item
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/get")
            let raw = try await APIClient.shared.postJSON(url, body: ["businessId": item.businessId])
            if let detail = parseSingleMessage(raw) {
                messageDetail = detail
            } else {
                messageDetail = item
            }
            await refreshUnread()
            await loadMessages(page: messagePage.pageNum)
        } catch {
            messageDetail = item
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    // MARK: - Version（Mac 客户端 DMG，不走服务端 jar 自更新）

    /// Bundle short version, e.g. `1.0.0` / `5.7.89`
    static var appMarketingVersion: String {
        let raw = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "1.0.0" : raw
    }

    func checkVersion() async {
        let current = Self.appMarketingVersion
        do {
            guard let release = try await fetchLatestMacDMGRelease() else {
                version = VersionCheckInfo(
                    needUpdate: false,
                    latestVersion: current,
                    currentVersion: current
                )
                return
            }
            let need = Self.compareVersion(current, release.tag) < 0
            version = VersionCheckInfo(
                needUpdate: need,
                latestVersion: release.tag,
                currentVersion: current,
                dmgURL: release.dmgURL.absoluteString,
                dmgFileName: release.dmgName
            )
        } catch {
            // Keep last known / silent — network optional for offline use
            if version.currentVersion.isEmpty {
                version = VersionCheckInfo(
                    needUpdate: false,
                    latestVersion: "",
                    currentVersion: current
                )
            }
        }
    }

    /// Confirm → download DMG to Downloads → open in Finder.
    func requestUpdate() {
        guard version.needUpdate, !updatePhase.isActive else { return }
        let target = version.latestVersion.isEmpty ? "新版本" : version.latestVersion
        guard AppAlert.confirm(
            title: "发现新版本",
            message: "将下载 Oci-Start \(target) 的 macOS 安装包（DMG）到「下载」文件夹并自动打开。\n请拖入「应用程序」后重新启动。",
            confirmTitle: "下载升级",
            cancelTitle: "稍后"
        ) else { return }

        Task { await self.executeDMGUpdate() }
    }

    func dismissUpdateProgress() {
        switch updatePhase {
        case .failed, .completed:
            updatePhase = .idle
            showUpdateProgress = false
        default:
            break
        }
    }

    func executeDMGUpdate() async {
        guard version.needUpdate else { return }
        guard let remote = URL(string: version.dmgURL), !version.dmgURL.isEmpty else {
            updatePhase = .failed("未找到 DMG 下载地址，请到 GitHub Releases 手动下载")
            showUpdateProgress = true
            return
        }

        showUpdateProgress = true
        updatePhase = .downloading(0)
        do {
            let bridge = VersionDownloadProgressBridge()
            bridge.onProgress = { [weak self] p in
                self?.updatePhase = .downloading(p)
            }
            let localURL = try await downloadDMG(from: remote, suggestedName: version.dmgFileName) { p in
                bridge.report(p)
            }
            updatePhase = .opening
            NSWorkspace.shared.open(localURL)
            version.needUpdate = false
            updatePhase = .completed(localURL.path)
        } catch {
            updatePhase = .failed(error.localizedDescription)
            ToastCenter.shared.error(error.localizedDescription)
        }
    }

    // MARK: GitHub Release helpers

    private struct MacDMGRelease {
        let tag: String
        let dmgURL: URL
        let dmgName: String
    }

    /// Prefer latest release that ships a `.dmg` (scan recent pages).
    private func fetchLatestMacDMGRelease() async throws -> MacDMGRelease? {
        guard let api = URL(string: "https://api.github.com/repos/doubleDimple/oci-start/releases?per_page=20") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("oci-start-mac", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.compatData(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.serverMessage("无法获取 GitHub 版本信息")
        }
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.serverMessage("GitHub Release 数据无效")
        }
        for rel in list {
            if (rel["draft"] as? Bool) == true { continue }
            if (rel["prerelease"] as? Bool) == true { continue }
            let tag = (rel["tag_name"] as? String) ?? ""
            guard !tag.isEmpty else { continue }
            guard let assets = rel["assets"] as? [[String: Any]] else { continue }
            if let dmg = Self.pickDMGAsset(assets) {
                return MacDMGRelease(tag: tag, dmgURL: dmg.url, dmgName: dmg.name)
            }
        }
        return nil
    }

    private static func pickDMGAsset(_ assets: [[String: Any]]) -> (url: URL, name: String)? {
        // Prefer names containing mac / OciStart, else first *.dmg
        var fallback: (URL, String)?
        for a in assets {
            let name = (a["name"] as? String) ?? ""
            guard name.lowercased().hasSuffix(".dmg") else { continue }
            guard let s = a["browser_download_url"] as? String, let u = URL(string: s) else { continue }
            let lower = name.lowercased()
            if lower.contains("mac") || lower.contains("ocistart") || lower.contains("oci-start") {
                return (u, name)
            }
            if fallback == nil { fallback = (u, name) }
        }
        return fallback.map { ($0.0, $0.1) }
    }

    private func downloadDMG(
        from remote: URL,
        suggestedName: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let safeName: String = {
            let n = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.lowercased().hasSuffix(".dmg") { return n }
            let ver = version.latestVersion.replacingOccurrences(of: "/", with: "-")
            return "OciStart-\(ver).dmg"
        }()
        let dest = downloads.appendingPathComponent(safeName)
        // Avoid overwrite race: if exists, append short id
        let finalDest: URL
        if FileManager.default.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            finalDest = downloads.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).dmg")
        } else {
            finalDest = dest
        }

        var req = URLRequest(url: remote)
        req.setValue("oci-start-mac", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 600
        try await URLSession.shared.compatDownload(for: req, to: finalDest, progress: progress)
        return finalDest
    }

    /// Same numeric compare as server `AppVersion` (v-5.7.89 vs 1.0.0).
    static func compareVersion(_ left: String, _ right: String) -> Int {
        let l = normalizeVersion(left).split(separator: ".").map { parseVersionPart(String($0)) }
        let r = normalizeVersion(right).split(separator: ".").map { parseVersionPart(String($0)) }
        let n = max(l.count, r.count)
        for i in 0..<n {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv { return lv < rv ? -1 : 1 }
        }
        return 0
    }

    private static func normalizeVersion(_ version: String) -> String {
        var s = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "0" }
        if s.lowercased().hasPrefix("v-") { s = String(s.dropFirst(2)) }
        else if s.lowercased().hasPrefix("v") { s = String(s.dropFirst()) }
        return s
    }

    private static func parseVersionPart(_ part: String) -> Int {
        var digits = ""
        for ch in part {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return Int(digits) ?? 0
    }

    // MARK: - Asset

    func openAssetAnalysis() {
        showAsset = true
        asset = nil
        assetError = nil
        Task { await loadAsset() }
    }

    func loadAsset() async {
        assetLoading = true
        assetError = nil
        defer { assetLoading = false }
        do {
            let url = try APIClient.shared.makeURL(
                session.serverURL,
                path: "/tenants/asset/analysis",
                query: ["cloudType": "\(session.cloudProvider)"]
            )
            let raw = try await APIClient.shared.getJSON(url)
            if let envSuccess = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]),
               let success = envSuccess["success"] as? Bool {
                if success, let data = envSuccess["data"] as? [String: Any] {
                    asset = parseAsset(data)
                    if let a = asset {
                        levelBadgeLevel = a.computedLevel
                        let cfg = AssetAnalysis.levelConfig(a.computedLevel)
                        levelBadgeTitle = a.levelTitle.isEmpty ? cfg.name : a.levelTitle
                    }
                } else {
                    assetError = (envSuccess["message"] as? String) ?? "加载失败"
                }
            }
        } catch {
            assetError = error.localizedDescription
        }
    }

    // MARK: - Parse helpers

    private func parseMessagePage(_ raw: Data, pageNum: Int) -> SysMessagePage {
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let success = obj["success"] as? Bool, success,
              let data = obj["data"] as? [String: Any] else {
            return SysMessagePage(pageNum: pageNum)
        }
        let contentArr = data["content"] as? [[String: Any]] ?? []
        let items = contentArr.compactMap { parseMessageDict($0) }
        let totalPages = (data["totalPages"] as? Int)
            ?? (data["totalPages"] as? Int64).map { Int($0) }
            ?? 0
        let totalElements = (data["totalElements"] as? Int)
            ?? (data["totalElements"] as? Int64).map { Int($0) }
            ?? items.count
        return SysMessagePage(
            content: items,
            totalPages: max(totalPages, 1),
            totalElements: totalElements,
            pageNum: pageNum
        )
    }

    private func parseSingleMessage(_ raw: Data) -> SysMessageItem? {
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let success = obj["success"] as? Bool, success,
              let data = obj["data"] as? [String: Any] else { return nil }
        return parseMessageDict(data)
    }

    private func parseMessageDict(_ d: [String: Any]) -> SysMessageItem? {
        let bid = (d["businessId"] as? String) ?? ""
        guard !bid.isEmpty else { return nil }
        let typeVal: String
        if let s = d["messageType"] as? String {
            typeVal = s
        } else {
            typeVal = "SYSTEM"
        }
        var time = ""
        if let s = d["createTime"] as? String {
            time = s.replacingOccurrences(of: "T", with: " ")
        } else if let arr = d["createTime"] as? [Int], arr.count >= 6 {
            time = String(format: "%04d-%02d-%02d %02d:%02d:%02d", arr[0], arr[1], arr[2], arr[3], arr[4], arr[5])
        }
        let read: Int
        if let r = d["readStatus"] as? Int { read = r }
        else if let r = d["readStatus"] as? Int64 { read = Int(r) }
        else { read = 1 }
        return SysMessageItem(
            businessId: bid,
            subject: (d["subject"] as? String) ?? "",
            content: (d["content"] as? String) ?? "",
            createTime: time,
            messageType: typeVal,
            readStatus: read
        )
    }

    private func parseAsset(_ d: [String: Any]) -> AssetAnalysis {
        var a = AssetAnalysis()
        if let n = d["totalCount"] as? Int { a.totalCount = n }
        else if let n = d["totalCount"] as? Int64 { a.totalCount = Int(n) }
        if let n = d["upgradeCount"] as? Int { a.upgradeCount = n }
        else if let n = d["upgradeCount"] as? Int64 { a.upgradeCount = Int(n) }
        if let n = d["freeCount"] as? Int { a.freeCount = n }
        else if let n = d["freeCount"] as? Int64 { a.freeCount = Int(n) }
        if let s = d["totalCost"] as? String { a.totalCost = s }
        else if let n = d["totalCost"] as? Double { a.totalCost = String(format: "%.2f", n) }
        else if let n = d["totalCost"] as? Int { a.totalCost = "\(n)" }
        if let n = d["level"] as? Int { a.level = n }
        a.levelTitle = (d["levelTitle"] as? String) ?? ""
        return a
    }

    private func stopPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        pollTimer?.invalidate()
    }
}
