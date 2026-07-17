import Foundation

// MARK: - Sheets

enum StorageSheet: Identifiable, Equatable {
    case createBucket
    case presigned(StorageObjectItem)
    case uploadProgress

    var id: String {
        switch self {
        case .createBucket: return "createBucket"
        case .presigned(let o): return "presign-\(o.name)"
        case .uploadProgress: return "upload"
        }
    }
}

// MARK: - Bucket

struct StorageBucketItem: Identifiable, Equatable {
    var name: String = ""
    var namespace: String = ""
    var timeCreated: String = ""
    var publicAccess: String = "NoPublicAccess"

    var id: String { "\(namespace)/\(name)" }

    var accessLabel: String {
        switch publicAccess {
        case "ObjectRead": return "公共读"
        case "ObjectReadWithoutList": return "公共读(无列表)"
        default: return "私有"
        }
    }

    var accessTone: StatusTone {
        publicAccess == "NoPublicAccess" || publicAccess.isEmpty ? .neutral : .info
    }

    var createdText: String {
        guard !timeCreated.isEmpty else { return "" }
        // ISO or "yyyy-MM-dd..."
        if timeCreated.count >= 16 {
            return String(timeCreated.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return timeCreated.replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Object

struct StorageObjectItem: Identifiable, Equatable {
    var name: String = ""
    var size: Int64 = 0
    var timeModified: String = ""

    var id: String { name }

    var displayName: String {
        if let r = name.range(of: "/", options: .backwards) {
            return String(name[r.upperBound...])
        }
        return name
    }

    var sizeText: String {
        StorageJSON.formatSize(size)
    }

    var modifiedText: String {
        guard !timeModified.isEmpty else { return "—" }
        if timeModified.count >= 16 {
            return String(timeModified.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return timeModified.replacingOccurrences(of: "T", with: " ")
    }

    var isPreviewable: Bool {
        let lower = name.lowercased()
        let exts = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf",
                    ".txt", ".log", ".md", ".json", ".xml", ".html", ".htm"]
        return exts.contains { lower.hasSuffix($0) }
    }
}

// MARK: - Upload task UI

struct StorageUploadTask: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var fileName: String = ""
    var fileURL: URL?
    var totalBytes: Int64 = 0
    var percent: Int = 0
    var statusText: String = "等待中"
    var failed: Bool = false
    var done: Bool = false
}

// MARK: - Page results

struct StorageBucketPage {
    var items: [StorageBucketItem] = []
    var nextPage: String?
}

struct StorageObjectPage {
    var items: [StorageObjectItem] = []
    var nextStartWith: String?
}

// MARK: - Access options

enum StorageAccessType: String, CaseIterable, Identifiable {
    case noPublic = "NoPublicAccess"
    case objectRead = "ObjectRead"
    case objectReadNoList = "ObjectReadWithoutList"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noPublic: return "私有（默认）"
        case .objectRead: return "公共读"
        case .objectReadNoList: return "公共读（无列表）"
        }
    }
}

// MARK: - JSON helpers

enum StorageJSON {
    static func obj(_ raw: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    static func string(_ any: Any?) -> String {
        guard let any = any else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if any is NSNull { return "" }
        return "\(any)"
    }

    static func int64(_ any: Any?) -> Int64 {
        guard let any = any else { return 0 }
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        if let n = any as? Double { return Int64(n) }
        if let n = any as? NSNumber { return n.int64Value }
        if let s = any as? String, let v = Int64(s) { return v }
        return 0
    }

    static func envelopeData(_ raw: Data) throws -> Any? {
        guard let root = obj(raw) else {
            throw APIError.serverMessage("响应解析失败")
        }
        if let success = root["success"] as? Bool, !success {
            let msg = string(root["message"]).isEmpty ? "操作失败" : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        if let code = root["code"] as? Int, code != 200, code != 0 {
            let msg = string(root["message"]).isEmpty ? "操作失败" : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        return root["data"]
    }

    static func ensureSuccess(_ raw: Data, fallback: String = "操作失败") throws {
        guard let root = obj(raw) else { return }
        if let success = root["success"] as? Bool, !success {
            let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
            throw APIError.serverMessage(msg)
        }
        if let code = root["code"] as? Int, code != 200, code != 0 {
            let msg = string(root["message"]).isEmpty ? fallback : string(root["message"])
            throw APIError.serverMessage(msg)
        }
    }

    static func parseBucket(_ d: [String: Any]) -> StorageBucketItem {
        var b = StorageBucketItem()
        b.name = string(d["name"])
        b.namespace = string(d["namespace"])
        b.timeCreated = string(d["timeCreated"])
        b.publicAccess = string(d["publicAccess"])
        if b.publicAccess.isEmpty { b.publicAccess = "NoPublicAccess" }
        return b
    }

    static func parseObject(_ d: [String: Any]) -> StorageObjectItem {
        var o = StorageObjectItem()
        o.name = string(d["name"])
        o.size = int64(d["size"])
        o.timeModified = string(d["timeModified"])
        return o
    }

    static func parseBucketPage(_ raw: Data) throws -> StorageBucketPage {
        let data = try envelopeData(raw)
        guard let dict = data as? [String: Any] else {
            throw APIError.serverMessage("存储桶列表解析失败")
        }
        let arr = (dict["items"] as? [[String: Any]]) ?? []
        var page = StorageBucketPage()
        page.items = arr.map { parseBucket($0) }
        let next = string(dict["nextPage"])
        page.nextPage = next.isEmpty ? nil : next
        return page
    }

    static func parseObjectPage(_ raw: Data) throws -> StorageObjectPage {
        let data = try envelopeData(raw)
        guard let dict = data as? [String: Any] else {
            throw APIError.serverMessage("对象列表解析失败")
        }
        let arr = (dict["items"] as? [[String: Any]]) ?? []
        var page = StorageObjectPage()
        page.items = arr.map { parseObject($0) }
        let next = string(dict["nextStartWith"])
        page.nextStartWith = next.isEmpty ? nil : next
        return page
    }

    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 0 { return "—" }
        if bytes == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024 && i < units.count - 1 {
            value /= 1024
            i += 1
        }
        if i == 0 {
            return "\(Int(value)) \(units[i])"
        }
        return String(format: "%.1f %@", value, units[i])
    }
}
