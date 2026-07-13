import Foundation
import Combine

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
        showMessages = true
        Task { await loadMessages(page: 1) }
    }

    func loadMessages(page: Int) async {
        messagesLoading = true
        defer { messagesLoading = false }
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/sysMessage/list")
            let raw = try await APIClient.shared.postJSON(url, body: [
                "pageNum": page,
                "pageSize": 5
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

    // MARK: - Version

    func checkVersion() async {
        do {
            let url = try APIClient.shared.makeURL(session.serverURL, path: "/api/version/check")
            let raw = try await APIClient.shared.getJSON(url)
            if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
                version = VersionCheckInfo(
                    needUpdate: (obj["needUpdate"] as? Bool) ?? false,
                    latestVersion: (obj["latestVersion"] as? String) ?? "",
                    currentVersion: (obj["currentVersion"] as? String) ?? ""
                )
            }
        } catch {
            // silent
        }
    }

    func executeUpdate() async {
        guard version.needUpdate else { return }
        await LoadingHUD.shared.during {
            do {
                let url = try APIClient.shared.makeURL(session.serverURL, path: "/api/version/execute-update")
                _ = try await APIClient.shared.postJSON(url, body: [
                    "version": version.latestVersion,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
                version.needUpdate = false
            } catch {
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
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
