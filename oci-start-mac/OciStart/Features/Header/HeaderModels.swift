import Foundation

// MARK: - System messages

struct SysMessageItem: Identifiable, Equatable {
    var id: String { businessId }
    let businessId: String
    let subject: String
    let content: String
    let createTime: String
    let messageType: String
    let readStatus: Int // 0 unread, 1 read

    var isUnread: Bool { readStatus == 0 }
}

struct SysMessagePage: Equatable {
    var content: [SysMessageItem] = []
    var totalPages: Int = 0
    var totalElements: Int = 0
    var pageNum: Int = 1
}

// MARK: - Version（Mac 客户端：GitHub Release DMG）

struct VersionCheckInfo: Equatable {
    var needUpdate: Bool = false
    var latestVersion: String = ""
    var currentVersion: String = ""
    /// GitHub asset browser_download_url for the .dmg
    var dmgURL: String = ""
    var dmgFileName: String = ""
}

/// Mac client upgrade UI: download DMG → open.
enum VersionUpdatePhase: Equatable {
    case idle
    /// Download progress 0…1
    case downloading(Double)
    /// Opening DMG in Finder
    case opening
    /// Local path of downloaded DMG
    case completed(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .completed: return false
        default: return true
        }
    }
}

/// Non-actor progress hop for URLSession download callbacks (macOS 11 concurrency-safe).
final class VersionDownloadProgressBridge: @unchecked Sendable {
    var onProgress: ((Double) -> Void)?

    func report(_ progress: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(progress)
        }
    }
}

// MARK: - Asset analysis

struct AssetAnalysis: Equatable {
    var totalCount: Int = 0
    var upgradeCount: Int = 0
    var freeCount: Int = 0
    var totalCost: String = "0"
    var level: Int = 1
    var levelTitle: String = ""

    var computedLevel: Int {
        // web calculateOracleLevel by totalCount
        let n = totalCount
        if n >= 200 { return 9 }
        if n >= 100 { return 8 }
        if n >= 60 { return 7 }
        if n >= 40 { return 6 }
        if n >= 25 { return 5 }
        if n >= 15 { return 4 }
        if n >= 8 { return 3 }
        if n >= 3 { return 2 }
        return 1
    }

    static func levelConfig(_ level: Int) -> (icon: String, name: String) {
        switch min(max(level, 1), 9) {
        case 1: return ("person", "初级云玩家")
        case 2: return ("star", "中级云达人")
        case 3: return ("star.fill", "高级架构师")
        case 4: return ("rosette", "资深资源商")
        case 5: return ("medal", "核心运营商")
        case 6: return ("bolt.fill", "顶级运营商")
        case 7: return ("flame.fill", "巅峰掌控者")
        case 8: return ("diamond.fill", "至尊领航员")
        default: return ("crown.fill", "Oracle 主宰者")
        }
    }
}

// MARK: - Locale

enum AppLocale: String, CaseIterable, Identifiable {
    case zhCN = "zh_CN"
    case zhTW = "zh_TW"
    case enUS = "en_US"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zhCN: return "简体中文"
        case .zhTW: return "繁體中文"
        case .enUS: return "English"
        }
    }
}
