import Foundation
import AppKit

struct MfaKeyItem: Identifiable, Equatable {
    let id: String
    var keyName: String
    var secretKey: String
    var issuer: String
    var qrCodeBase64: String
    var otpCode: String
    var revealSecret: Bool
}

struct MfaAddForm: Identifiable, Equatable {
    let id = UUID()
    var keyName = ""
    var secretKey = ""
}

enum MfaBackupJSON {
    static func parseList(_ data: Data) throws -> [MfaKeyItem] {
        guard let root = obj(data) else {
            throw APIError.serverMessage("MFA 列表解析失败")
        }
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage(str(root["message"]).isEmpty ? "加载 MFA 失败" : str(root["message"]))
        }
        let arr = (root["data"] as? [[String: Any]])
            ?? ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]])
            ?? []
        return arr.compactMap { d in
            let name = str(d["keyName"])
            let secret = str(d["secretKey"])
            guard !name.isEmpty, !secret.isEmpty else { return nil }
            return MfaKeyItem(
                id: name,
                keyName: name,
                secretKey: secret,
                issuer: str(d["issuer"]).isEmpty ? "Default" : str(d["issuer"]),
                qrCodeBase64: str(d["qrCode"]),
                otpCode: "------",
                revealSecret: false
            )
        }
    }

    static func parseBatchOtp(_ data: Data) -> [String: String] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return [:]
        }
        var map: [String: String] = [:]
        for d in arr {
            let secret = str(d["secretKey"])
            let code = str(d["otpCode"])
            if !secret.isEmpty, !code.isEmpty {
                map[secret] = code
            }
        }
        return map
    }

    static func parseDelete(_ data: Data) throws {
        if data.isEmpty { return }
        if let root = obj(data) {
            let msg = str(root["message"]).isEmpty ? str(root["otpCode"]) : str(root["message"])
            // OtpResponse2 often returns { otpCode: "OK" } or message
            if msg.lowercased().contains("null") {
                throw APIError.serverMessage("删除失败")
            }
        }
    }

    static func qrImage(from base64: String) -> NSImage? {
        var s = base64
        if let range = s.range(of: "base64,") {
            s = String(s[range.upperBound...])
        }
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { return nil }
        return NSImage(data: data)
    }

    static func obj(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
}
