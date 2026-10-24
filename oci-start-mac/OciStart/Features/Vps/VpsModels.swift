import Foundation

/// Values come only from actual monitoring reports. A missing metric is never zero.
struct VpsLiveMetrics: Equatable {
    var cpuPercent: Double?
    var memPercent: Double?
    var diskPercent: Double?
    var diskTotalLabel = "—"
    var load = "—"
    var uptime = "—"
    var netRx = "—"
    var netTx = "—"
    var lastBeatMs: Int64 = 0
    var hasData = false
}

struct VpsCardItem: Identifiable, Equatable {
    var item: InstanceItem
    var metrics = VpsLiveMetrics()
    var latencyMs: Int?
    var isLatencyTesting = false
    var monitorWarning = false
    var id: String { item.id }
    var isOnline: Bool { item.onLineEnable == 1 }
    var specText: String {
        let cpu = item.ocpus > 0 ? "\(item.ocpus) CPU" : "—"
        let mem = item.memoryInGBs > 0 ? "\(item.memoryInGBs) GiB" : "—"
        return "\(cpu) / \(mem)"
    }
    var maskedIP: String { item.publicIps.isEmpty ? "—" : "••••••" }
    var displayIP: String { item.publicIps.isEmpty ? "—" : item.publicIps }
}

enum VpsFormat {
    static func bytes(_ bytes: Double) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var value = bytes
        var index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return String(format: "%.1f %@", value, units[index])
    }
    static func sizeMB(_ mb: Double) -> String { String(format: "%.1f GiB", mb / 1024) }
    static func uptime(_ seconds: Double) -> String {
        let days = Int(seconds / 86400), hours = Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600)
        return "\(days)d \(hours)h"
    }
    static func metric(_ value: Double?, suffix: String = "%") -> String {
        value.map { String(format: "%.1f", $0) + suffix } ?? "—"
    }
    static func latencyLabel(_ ms: Int?) -> String {
        guard let ms = ms else { return "—" }
        return ms < 0 ? vpsText("请求失败", "Request failed") : "\(ms) ms"
    }
    static func date(_ milliseconds: Int64) -> String {
        guard milliseconds > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLocale") ?? "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
    }
}

func vpsText(_ zh: String, _ en: String) -> String {
    (UserDefaults.standard.string(forKey: "appLocale") ?? "").hasPrefix("en") ? en : zh
}

struct NetworkQualityTask: Codable, Identifiable, Equatable {
    var id: String
    var version: String
    var name: String
    var operatorCode: String
    var region: String
    var type: String
    var target: String
    var intervalSeconds: Int
    var sampleCount: Int
    var enabled: Bool
    var instanceIds: [String]
    var createdAt: Int64
    var updatedAt: Int64
    enum CodingKeys: String, CodingKey {
        case id, version, name, region, type, target, intervalSeconds, sampleCount, enabled, instanceIds, createdAt, updatedAt
        case operatorCode = "operator"
    }
    var payload: [String: Any] {
        ["name": name.trimmingCharacters(in: .whitespacesAndNewlines), "operator": operatorCode,
         "region": region.trimmingCharacters(in: .whitespacesAndNewlines), "type": type,
         "target": target.trimmingCharacters(in: .whitespacesAndNewlines),
         "intervalSeconds": intervalSeconds, "sampleCount": sampleCount, "enabled": enabled, "instanceIds": instanceIds]
    }
    static func draft(instanceID: String? = nil) -> NetworkQualityTask {
        NetworkQualityTask(id: "", version: "0", name: "", operatorCode: "custom", region: "", type: "icmp",
                           target: "", intervalSeconds: 60, sampleCount: 3, enabled: true,
                           instanceIds: instanceID.map { [$0] } ?? [], createdAt: 0, updatedAt: 0)
    }
    var operatorLabel: String {
        switch operatorCode {
        case "telecom": return vpsText("电信", "Telecom")
        case "unicom": return vpsText("联通", "Unicom")
        case "mobile": return vpsText("移动", "Mobile")
        default: return vpsText("自定义", "Custom")
        }
    }
    func validate() throws {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = self.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, region.count <= 80,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !region.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              ["icmp", "tcp", "http"].contains(type), ["telecom", "unicom", "mobile", "custom"].contains(operatorCode),
              (30...86400).contains(intervalSeconds), (1...10).contains(sampleCount),
              (1...256).contains(instanceIds.count), Set(instanceIds).count == instanceIds.count,
              instanceIds.allSatisfy({ Int64($0).map { $0 > 0 } ?? false }),
              !target.isEmpty, target.count <= 2048, target.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { throw APIError.serverMessage(vpsText("请检查任务名称、目标、采样数、间隔和实例。", "Check the task name, target, samples, interval and instances.")) }
        let candidate = type == "http" ? target : "http://\(target)"
        guard let url = URLComponents(string: candidate), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              type != "http" || ["http", "https"].contains(url.scheme ?? ""),
              type != "icmp" || (url.port == nil && url.path.isEmpty && url.query == nil),
              type != "tcp" || (url.port.map { (1...65535).contains($0) } ?? false) && url.path.isEmpty && url.query == nil
        else { throw APIError.serverMessage(vpsText("目标格式无效。ICMP 使用主机，TCP 使用主机:端口，HTTP 使用完整 URL。", "Use a host for ICMP, host:port for TCP, or a complete HTTP URL.")) }
    }
}

struct NetworkQualityAgent: Decodable, Identifiable {
    var id: String
    var instanceId: String
    var displayName: String?
    var publicIps: String?
    var tenancyName: String?
    var regionName: String?
    var cloudType: Int?
    var monitorInstalled: Bool?
    var qualityStatus: String
    var lastSeen: Int64?
    var version: String?
    var title: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
    var statusLabel: String {
        switch qualityStatus {
        case "online": return vpsText("在线", "Online")
        case "offline": return vpsText("离线", "Offline")
        case "upgrade_required": return vpsText("需要升级探针", "Agent upgrade required")
        default: return vpsText("未安装", "Not installed")
        }
    }
}

struct NetworkQualityResult: Decodable, Identifiable {
    var instanceId: String
    var taskId: String
    var revision: String
    var executionId: String
    var updatedAt: Int64
    var status: String
    var attempts: Int?
    var successful: Int?
    var avgMs: Double?
    var minMs: Double?
    var maxMs: Double?
    var errorCode: String?
    var errorMessage: String?
    var httpStatus: Int?
    var id: String { executionId }
    var lossPercent: Double? {
        guard let attempts = attempts, attempts > 0, let successful = successful,
              successful >= 0, successful <= attempts else { return nil }
        return Double(attempts - successful) / Double(attempts) * 100
    }
    var statusLabel: String {
        switch status {
        case "success": return vpsText("成功", "Success")
        case "partial": return vpsText("部分成功", "Partial")
        case "failed": return vpsText("失败", "Failed")
        case "unsupported": return vpsText("不支持", "Unsupported")
        case "error": return vpsText("执行错误", "Error")
        default: return vpsText("未知", "Unknown")
        }
    }
}

struct NetworkQualityOverview: Decodable {
    var tasks: [NetworkQualityTask]
    var agents: [NetworkQualityAgent]
    var latest: [NetworkQualityResult]
    var serverTime: Int64
    var legacyDisabled: Bool
}

struct NetworkQualityStats: Decodable {
    var count: Int
    var attempts: Int
    var successful: Int
    var avgMs: Double?
    var minMs: Double?
    var maxMs: Double?
    var lossPercent: Double?
}

struct NetworkQualityHistory: Decodable {
    var instanceId: String
    var taskId: String
    var revision: String
    var hours: Int
    var from: Int64
    var to: Int64
    var points: [NetworkQualityResult]
    var totalPoints: Int
    var truncated: Bool
    var stats: NetworkQualityStats
}

/// A dispatched mutation with an unconfirmed outcome is never automatically retried.
struct NetworkQualityMutationError: LocalizedError {
    let message: String
    let needsReview: Bool
    var errorDescription: String? { message }
}
