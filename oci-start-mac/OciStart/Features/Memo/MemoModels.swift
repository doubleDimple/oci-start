import Foundation

struct MemoItem: Identifiable, Equatable {
    let id: Int64
    var title: String
    var summary: String
    var content: String
    var createTime: String
    var updateTime: String
}

struct MemoFormState: Identifiable, Equatable {
    var id: Int64?
    var title = ""
    var summary = ""
    var content = ""

    var isNew: Bool { id == nil }
}

enum MemoJSON {
    static func parseList(_ data: Data) throws -> [MemoItem] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            // { success, data: [...] }
            if let root = obj(data), let dataArr = root["data"] as? [[String: Any]] {
                return dataArr.compactMap(parseOne)
            }
            throw APIError.serverMessage("备忘列表解析失败")
        }
        return arr.compactMap(parseOne)
    }

    static func parseOne(_ d: [String: Any]) -> MemoItem? {
        let id = int64(d["id"])
        guard id > 0 else { return nil }
        return MemoItem(
            id: id,
            title: str(d["title"]),
            summary: str(d["summary"]),
            content: str(d["content"]),
            createTime: str(d["createTime"]),
            updateTime: str(d["updateTime"])
        )
    }

    static func parseOneData(_ data: Data) throws -> MemoItem {
        guard let root = obj(data) else { throw APIError.serverMessage("备忘解析失败") }
        if let item = parseOne(root) { return item }
        if let nested = root["data"] as? [String: Any], let item = parseOne(nested) { return item }
        throw APIError.serverMessage("备忘解析失败")
    }

    static func obj(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if let arr = v as? [Any] {
            // LocalDateTime array e.g. [2024,11,24,12,0,0]
            return arr.map { "\($0)" }.joined(separator: "-")
        }
        return ""
    }

    static func int64(_ v: Any?) -> Int64 {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let i = Int64(s) { return i }
        return 0
    }
}
