import Foundation
import AppKit

struct MfaKeyItem: Identifiable, Equatable {
    let id: String
    let keyName: String
    let issuer: String
    let createTime: String
    let revision: String
}

struct MfaCandidate: Identifiable, Equatable {
    let id = UUID()
    var keyName: String
    var issuer: String
    var secretKey: String
    var payload: [String: String] { ["keyName": keyName, "issuer": issuer, "secretKey": secretKey] }
}

struct MfaMaterial: Identifiable {
    let id: String
    let keyName: String
    let issuer: String
    let secretKey: String
    let qrCode: String
}

struct MfaBackupFailure: LocalizedError {
    let message: String
    var writeAttempted = false
    var errorDescription: String? { message }
}

enum MfaBackupJSON {
    static func object(_ data: Data, write: Bool = false) throws -> [String: Any] {
        guard data.count <= 16 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MfaBackupFailure(message: "MFA 响应格式无效", writeAttempted: write)
        }
        guard root["success"] as? Bool == true else {
            let key = root["errorKey"] as? String ?? ""
            let messages = ["conflict": "账户已变更，请刷新后重试", "invalidSecret": "密钥无效",
                "invalidInput": "请检查账户名称和密钥", "invalidUri": "二维码内容无效",
                "unsupportedParameters": "不支持该二维码的 OTP 参数", "notFound": "账户已不存在",
                "qrNotFound": "图片中未找到二维码", "invalidImage": "图片无效",
                "imageTooLarge": "图片不能超过 5 MiB", "limitExceeded": "账户数量超过上限"]
            throw MfaBackupFailure(message: messages[key] ?? "MFA 操作未完成",
                writeAttempted: write && root["writeAttempted"] as? Bool != false)
        }
        return root
    }

    static func text(_ value: Any?) -> String { value as? String ?? "" }
    static func entry(_ value: [String: Any]) throws -> MfaKeyItem {
        let id = text(value["id"]), revision = text(value["revision"])
        guard let number = Int64(id), number > 0, String(number) == id,
              revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let name = value["keyName"] as? String, let issuer = value["issuer"] as? String else {
            throw MfaBackupFailure(message: "MFA 账户数据无效")
        }
        return MfaKeyItem(id: id, keyName: name, issuer: issuer, createTime: text(value["createTime"]), revision: revision)
    }

    static func qrImage(from base64: String) -> NSImage? {
        guard base64.hasPrefix("iVBORw0KGgo"), let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
