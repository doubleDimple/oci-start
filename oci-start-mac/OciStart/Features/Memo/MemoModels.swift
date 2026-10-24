import Foundation
import CoreFoundation

struct MemoItem: Identifiable, Hashable {
    let id: Int64
    var title: String
    var summary: String
    var content: String
    var htmlContent: String?
    var createTime: String
    var updateTime: String
    var revision: String?
}

struct MemoFormState: Equatable {
    var id: Int64?
    var title = ""
    var summary = ""
    var content = ""
    var htmlContent: String?
    var revision: String?
    var isNew: Bool { id == nil }

    init(item: MemoItem? = nil) {
        id = item?.id
        title = item?.title ?? ""
        summary = item?.summary ?? ""
        content = item?.content ?? ""
        htmlContent = item?.htmlContent
        revision = item?.revision
    }

    func normalized() throws -> MemoFormState {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.title.isEmpty, result.title.utf16.count <= 255, result.summary.utf16.count <= 200,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.utf8.count <= 65_535, (htmlContent?.utf8.count ?? 0) <= 65_535 else {
            throw MemoFailure(key: .invalidInput)
        }
        // Body indentation and leading/trailing whitespace are user content.
        return result
    }
}

struct MemoFailure: LocalizedError {
    enum Key { case invalidInput, invalidResponse, requestFailed, unauthorized, forbidden, notFound, conflict }
    let key: Key
    var writeAttempted = false

    var errorDescription: String? {
        let language = LanguageManager.shared
        switch key {
        case .invalidInput: return language.text("请填写标题和正文；标题最多 255 字、摘要最多 200 字，正文与富文本各不超过 65,535 字节。", "Enter a title and body. Title: 255 characters; summary: 200; text and HTML: 65,535 bytes each.")
        case .invalidResponse: return language.text("笔记响应格式无效，请检查服务端版本后重新读取。", "Invalid note response. Check the server version and reload.")
        case .requestFailed: return language.text("笔记请求失败，请检查连接后重新读取。", "The note request failed. Check the connection and reload.")
        case .unauthorized: return language.text("登录已过期，请重新登录。", "Your session expired. Sign in again.")
        case .forbidden: return language.text("当前账号无权操作笔记。", "This account cannot access these notes.")
        case .notFound: return language.text("这条笔记已被删除，草稿仍保留。", "This note was deleted. Your draft is retained.")
        case .conflict: return language.text("笔记已在其他位置更新。请对照最新保存版本，或将草稿另存为新笔记。", "The note changed elsewhere. Compare the saved version or keep this draft as a new note.")
        }
    }
}

enum MemoJSON {
    static func parseList(_ data: Data) throws -> [MemoItem] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MemoFailure(key: .invalidResponse)
        }
        let items = try array.map(parseOne)
        guard Set(items.map(\.id)).count == items.count else { throw MemoFailure(key: .invalidResponse) }
        return items
    }

    static func parseOne(_ object: [String: Any]) throws -> MemoItem {
        let identifier: Int64?
        if let string = object["id"] as? String {
            identifier = Int64(string)
        } else if let number = object["id"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() {
            identifier = Int64(number.stringValue)
        } else { identifier = nil }
        guard let id = identifier, id > 0 else { throw MemoFailure(key: .invalidResponse) }
        return MemoItem(id: id, title: try text(object["title"]), summary: try text(object["summary"]),
                        content: try text(object["content"]), htmlContent: try optionalText(object["htmlContent"]),
                        createTime: try text(object["createTime"]), updateTime: try text(object["updateTime"]), revision: nil)
    }

    static func parseOneData(_ data: Data, expectedID: Int64? = nil) throws -> MemoItem {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MemoFailure(key: .invalidResponse)
        }
        let item = try parseOne(object)
        guard expectedID == nil || item.id == expectedID else { throw MemoFailure(key: .invalidResponse) }
        return item
    }

    static func parseGuarded(_ data: Data, id: Int64) throws -> MemoItem {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = root["memo"] as? [String: Any], let revision = root["revision"] as? String,
              validRevision(revision) else { throw MemoFailure(key: .invalidResponse) }
        var item = try parseOne(object)
        guard item.id == id else { throw MemoFailure(key: .invalidResponse) }
        item.revision = revision
        return item
    }

    static func validRevision(_ revision: String?) -> Bool {
        guard let revision = revision, revision.count == 64 else { return false }
        return revision.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    private static func optionalText(_ value: Any?) throws -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw MemoFailure(key: .invalidResponse) }
        return text
    }
    private static func text(_ value: Any?) throws -> String { try optionalText(value) ?? "" }
}
