import Foundation

// MARK: - Live metrics (WebSocket `/ws/monitor`)

struct VpsLiveMetrics: Equatable {
    var cpuPercent: Double = 0
    var memPercent: Double = 0
    var diskPercent: Double = 0
    var diskTotalLabel: String = ""
    var load: String = ""
    var uptime: String = ""
    var netRx: String = "0 B/s"
    var netTx: String = "0 B/s"
    var lastBeatMs: Int64 = 0
    var hasData: Bool = false
}

// MARK: - Card presentation

struct VpsCardItem: Identifiable, Equatable {
    var item: InstanceItem
    var metrics: VpsLiveMetrics = VpsLiveMetrics()
    /// 浏览器侧延迟 ms；-1 超时；nil 未测
    var latencyMs: Int? = nil
    var isLatencyTesting: Bool = false
    var monitorWarning: Bool = false

    var id: String { item.id }

    var isOnline: Bool { item.isPingOnline }

    var archClass: String {
        let a = item.architecture.uppercased()
        if a.contains("ARM") { return "arm" }
        if a.contains("AMD") || a.contains("X86") { return "amd" }
        return "other"
    }

    var specText: String {
        let cpu = item.ocpus
        let mem = item.memoryInGBs
        let disk = item.bootVolumeSizeInGBs
        if cpu > 0 || mem > 0 {
            return "\(cpu)C\(mem)G · \(disk > 0 ? "\(disk)GB" : "—")"
        }
        return item.cpuAndMem
    }

    var maskedIP: String {
        let ip = item.publicIps.trimmingCharacters(in: .whitespacesAndNewlines)
        if ip.isEmpty { return "无 IP" }
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).*** .***.\(parts[3])".replacingOccurrences(of: " ", with: "")
        }
        if ip.count > 6 {
            return "\(ip.prefix(3))***\(ip.suffix(2))"
        }
        return "***"
    }

    var displayIP: String {
        let ip = item.publicIps.trimmingCharacters(in: .whitespacesAndNewlines)
        return ip.isEmpty ? "无 IP" : ip
    }
}

enum VpsFormat {
    static func speed(_ bytes: Double) -> String {
        if bytes <= 0 { return "0 B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bytes
        var i = 0
        while v >= 1024, i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return String(format: "%.1f %@", v, units[i])
    }

    static func sizeMB(_ mb: Double) -> String {
        if mb > 1024 { return String(format: "%.0fG", mb / 1024) }
        return String(format: "%.0fM", mb)
    }

    static func uptime(_ seconds: Double) -> String {
        let d = Int(seconds / 86_400)
        let h = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600)
        if d > 0 { return "\(d)天" }
        if h > 0 { return "\(h)小时" }
        return "\(max(1, Int(seconds / 60)))分"
    }

    static func latencyLabel(_ ms: Int?) -> String {
        guard let ms = ms else { return "—" }
        if ms < 0 { return "超时" }
        return "\(ms)ms"
    }
}
