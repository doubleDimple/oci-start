import Foundation

// MARK: - API envelope (matches com.doubledimple.ocicommon.param.ApiResponse)

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let data: T?
    let code: Int?
}

// MARK: - /boot/dashboard-stats → DashboardStats

struct DashboardStats: Decodable, Equatable {
    var totalApiCalls: Int64 = 0
    var totalBootInstances: Int64 = 0
    var totalAttempts: Int64 = 0
    var successfulAttempts: Int64 = 0
    var successRate: Int64 = 0
    var failCounts: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case totalApiCalls, totalBootInstances, totalAttempts
        case successfulAttempts, successRate, failCounts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalApiCalls = try Self.decodeInt64(c, forKey: .totalApiCalls)
        totalBootInstances = try Self.decodeInt64(c, forKey: .totalBootInstances)
        totalAttempts = try Self.decodeInt64(c, forKey: .totalAttempts)
        successfulAttempts = try Self.decodeInt64(c, forKey: .successfulAttempts)
        successRate = try Self.decodeInt64(c, forKey: .successRate)
        failCounts = try Self.decodeInt64(c, forKey: .failCounts)
    }

    private static func decodeInt64(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Int64(v) }
        if let v = try? c.decode(Double.self, forKey: key) { return Int64(v) }
        return 0
    }
}

// MARK: - /monitor/stats → SystemMetrics

struct SystemMetrics: Decodable, Equatable {
    var cpuUsage: Double = 0
    var cpuTemperature: Double = 0
    var cpuPhysicalCount: Int = 0
    var cpuLogicalCount: Int = 0
    var cpuModel: String = ""
    var cpuFrequency: Double = 0

    var memoryUsage: Double = 0
    /// MB (same as web JS: totalMemory / 1024 → GB)
    var totalMemory: Double = 0
    var availableMemory: Double = 0
    var usedMemory: Double = 0
    var swapUsage: Double = 0
    var swapTotal: Double = 0
    var swapUsed: Double = 0

    var diskUsage: Double = 0
    var diskTotal: Double = 0
    var diskUsed: Double = 0
    var diskFree: Double = 0

    /// KB/s
    var uploadSpeed: Double = 0
    var downloadSpeed: Double = 0
    var totalUploadBytes: Double = 0
    var totalDownloadBytes: Double = 0

    var totalProcesses: Int = 0
    var threadCount: Int = 0
    var systemUptime: Double = 0
    var osName: String = ""
    var osArch: String = ""
    var hostname: String = ""
    var timestamp: String = ""

    enum CodingKeys: String, CodingKey {
        case cpuUsage, cpuTemperature, cpuPhysicalCount, cpuLogicalCount, cpuModel, cpuFrequency
        case memoryUsage, totalMemory, availableMemory, usedMemory, swapUsage, swapTotal, swapUsed
        case diskUsage, diskTotal, diskUsed, diskFree
        case uploadSpeed, downloadSpeed, totalUploadBytes, totalDownloadBytes
        case totalProcesses, threadCount, systemUptime, osName, osArch, hostname, timestamp
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpuUsage = Self.d(c, .cpuUsage)
        cpuTemperature = Self.d(c, .cpuTemperature)
        cpuPhysicalCount = Self.i(c, .cpuPhysicalCount)
        cpuLogicalCount = Self.i(c, .cpuLogicalCount)
        cpuModel = (try? c.decode(String.self, forKey: .cpuModel)) ?? ""
        cpuFrequency = Self.d(c, .cpuFrequency)

        memoryUsage = Self.d(c, .memoryUsage)
        totalMemory = Self.d(c, .totalMemory)
        availableMemory = Self.d(c, .availableMemory)
        usedMemory = Self.d(c, .usedMemory)
        swapUsage = Self.d(c, .swapUsage)
        swapTotal = Self.d(c, .swapTotal)
        swapUsed = Self.d(c, .swapUsed)

        diskUsage = Self.d(c, .diskUsage)
        diskTotal = Self.d(c, .diskTotal)
        diskUsed = Self.d(c, .diskUsed)
        diskFree = Self.d(c, .diskFree)

        uploadSpeed = Self.d(c, .uploadSpeed)
        downloadSpeed = Self.d(c, .downloadSpeed)
        totalUploadBytes = Self.d(c, .totalUploadBytes)
        totalDownloadBytes = Self.d(c, .totalDownloadBytes)

        totalProcesses = Self.i(c, .totalProcesses)
        threadCount = Self.i(c, .threadCount)
        systemUptime = Self.d(c, .systemUptime)
        osName = (try? c.decode(String.self, forKey: .osName)) ?? ""
        osArch = (try? c.decode(String.self, forKey: .osArch)) ?? ""
        hostname = (try? c.decode(String.self, forKey: .hostname)) ?? ""

        if let s = try? c.decode(String.self, forKey: .timestamp) {
            timestamp = s
        } else if let arr = try? c.decode([Int].self, forKey: .timestamp), arr.count >= 6 {
            // Jackson LocalDateTime array: [y,m,d,h,mi,s,...]
            timestamp = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                               arr[0], arr[1], arr[2], arr[3], arr[4], arr[5])
        } else {
            timestamp = ""
        }
    }

    private static func d(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Double {
        if let v = try? c.decode(Double.self, forKey: k) { return v }
        if let v = try? c.decode(Int64.self, forKey: k) { return Double(v) }
        if let v = try? c.decode(Int.self, forKey: k) { return Double(v) }
        return 0
    }

    private static func i(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int {
        if let v = try? c.decode(Int.self, forKey: k) { return v }
        if let v = try? c.decode(Int64.self, forKey: k) { return Int(v) }
        if let v = try? c.decode(Double.self, forKey: k) { return Int(v) }
        return 0
    }
}

// MARK: - Format helpers (match web dashboard.js)

enum DashboardFormat {
    static func size(_ bytes: Double) -> String {
        if bytes <= 0 { return "0 B" }
        let k = 1024.0
        let sizes = ["B", "KB", "MB", "GB", "TB"]
        let i = max(0, min(sizes.count - 1, Int(floor(log(bytes) / log(k)))))
        let value = bytes / pow(k, Double(i))
        return String(format: "%.2f %@", value, sizes[i])
    }

    /// Memory fields from backend are MB → convert to bytes like web JS.
    static func memoryMB(_ mb: Double) -> String {
        size(mb * 1024 * 1024)
    }

    /// uploadSpeed / downloadSpeed are KB/s
    static func speed(_ kbps: Double) -> String {
        if kbps < 1024 {
            return String(format: "%.2f KB/s", kbps)
        }
        return String(format: "%.2f MB/s", kbps / 1024)
    }

    static func uptime(_ seconds: Double) -> String {
        let s = Int64(seconds)
        let years = s / (86400 * 365)
        let days = (s % (86400 * 365)) / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        var parts: [String] = []
        if years > 0 { parts.append("\(years)year") }
        if days > 0 { parts.append("\(days)day") }
        if hours > 0 { parts.append("\(hours)hour") }
        if minutes > 0 { parts.append("\(minutes)min") }
        return parts.isEmpty ? "0min" : parts.joined(separator: " ")
    }

    static func uptimeDays(_ seconds: Double) -> String {
        let days = Int(seconds / 86400)
        return "\(days)天"
    }
}

struct NetworkSample: Identifiable, Equatable {
    let id = UUID()
    let timeLabel: String
    let upload: Double
    let download: Double
}
