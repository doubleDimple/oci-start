import Foundation
import AppKit
import SwiftUI

// MARK: - Form state (align `/api/system/securitySettingsConfigs`)

struct GithubOAuthForm: Equatable {
    var enabled: Bool = false
    var username: String = ""
    var githubId: String = ""
    var clientId: String = ""
    var clientSecret: String = ""
    var hasClientSecret = false
    var secretMode: NativeSecretMode = .replace
    var redirectUri: String = ""
}

struct GoogleOAuthForm: Equatable {
    var enabled: Bool = false
    var email: String = ""
    var clientId: String = ""
    var clientSecret: String = ""
    var hasClientSecret = false
    var secretMode: NativeSecretMode = .replace
    var redirectUri: String = ""
}

struct MfaForm: Equatable {
    var enabled: Bool = false
    var issuer: String = "OCI-Start Verify"
    var secretKey: String = ""
    var hasSecretKey = false
    var qrCodeBase64: String = ""
    var verifyCode: String = ""
}

struct TurnstileForm: Equatable {
    var enabled: Bool = false
    var siteKey: String = ""
    var secretKey: String = ""
    var hasSecretKey = false
    var secretMode: NativeSecretMode = .replace
}

struct SecuritySettingsSnapshot: Equatable {
    var currentUsername: String = ""
    var siteLogoName: String = "OCI-START"
    var github: GithubOAuthForm = GithubOAuthForm()
    var google: GoogleOAuthForm = GoogleOAuthForm()
    var mfa: MfaForm = MfaForm()
    var turnstile: TurnstileForm = TurnstileForm()
    var channelNotifyEnabled: Bool = false
}

enum SecuritySettingsJSON {
    static func parse(_ data: Data) throws -> SecuritySettingsSnapshot {
        guard let root = obj(data) else {
            throw APIError.serverMessage("配置解析失败")
        }
        if let success = root["success"] as? Bool, success == false {
            throw APIError.serverMessage((root["message"] as? String) ?? "加载配置失败")
        }
        guard root["success"] as? Bool == true, let payload = root["data"] as? [String: Any],
              ["github", "google", "mfa", "turnstile"].allSatisfy({ payload[$0] is [String: Any] }) else { throw APIError.invalidResponse }
        var out = SecuritySettingsSnapshot()
        out.currentUsername = str(payload["currentUsername"])
        out.siteLogoName = str(payload["siteLogoName"]).isEmpty ? "OCI-START" : str(payload["siteLogoName"])
        guard let channelEnabled = payload["channelNotifyEnabled"] as? Bool else { throw APIError.invalidResponse }
        out.channelNotifyEnabled = channelEnabled

        if let g = payload["github"] as? [String: Any] {
            guard let enabled = g["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.github.enabled = enabled
            out.github.username = firstNonEmpty(str(g["userName"]), str(g["username"]))
            out.github.githubId = str(g["githubId"])
            out.github.clientId = str(g["clientId"])
            guard let hasSecret = g["hasClientSecret"] as? Bool else { throw APIError.invalidResponse }
            out.github.hasClientSecret = hasSecret
            out.github.secretMode = hasSecret ? .keep : .replace
            out.github.redirectUri = str(g["redirectUri"])
        }
        if let g = payload["google"] as? [String: Any] {
            guard let enabled = g["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.google.enabled = enabled
            out.google.email = str(g["email"])
            out.google.clientId = str(g["clientId"])
            guard let hasSecret = g["hasClientSecret"] as? Bool else { throw APIError.invalidResponse }
            out.google.hasClientSecret = hasSecret
            out.google.secretMode = hasSecret ? .keep : .replace
            out.google.redirectUri = str(g["redirectUri"])
        }
        if let m = payload["mfa"] as? [String: Any] {
            guard let enabled = m["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.mfa.enabled = enabled
            out.mfa.issuer = str(m["issuer"]).isEmpty ? "OCI-Start Verify" : str(m["issuer"])
            guard let hasSecret = m["hasSecretKey"] as? Bool else { throw APIError.invalidResponse }
            out.mfa.hasSecretKey = hasSecret
        }
        if let t = payload["turnstile"] as? [String: Any] {
            guard let enabled = t["enabled"] as? Bool else { throw APIError.invalidResponse }
            out.turnstile.enabled = enabled
            out.turnstile.siteKey = str(t["siteKey"])
            guard let hasSecret = t["hasSecretKey"] as? Bool else { throw APIError.invalidResponse }
            out.turnstile.hasSecretKey = hasSecret
            out.turnstile.secretMode = hasSecret ? .keep : .replace
        }
        return out
    }

    /// These configuration endpoints acknowledge a successful write with an empty body.
    static func ensureOK(_ data: Data, fallback: String) throws {
        guard String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
            throw APIError.serverMessage(fallback)
        }
    }

    static func parseApiResponse(_ data: Data, fallback: String) throws -> String {
        guard let root = obj(data), root["success"] as? Bool == true else {
            throw APIError.serverMessage("验证码未通过验证")
        }
        return "验证码验证成功，此操作不会启用或保存 MFA。"
    }

    static func qrImage(from base64: String) -> NSImage? {
        let cleaned = base64
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = Data(base64Encoded: cleaned) else { return nil }
        return NSImage(data: data)
    }

    // helpers

    static func obj(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }

    static func firstNonEmpty(_ values: String...) -> String {
        for v in values where !v.isEmpty { return v }
        return ""
    }
}


/// A saved secret is represented only by its existence flag, never by a mask sent back to the server.
enum NativeSecretMode: String, CaseIterable {
    case keep, replace, clear
    var title: String {
        switch self {
        case .keep: return LanguageManager.shared.text("保留已保存值", "Keep saved value")
        case .replace: return LanguageManager.shared.text("替换为新值", "Replace with a new value")
        case .clear: return LanguageManager.shared.text("明确清除", "Clear saved value")
        }
    }

    func validate(_ value: String, hasSaved: Bool, required: Bool) throws {
        if self == .keep && !hasSaved { throw APIError.serverMessage("没有可保留的已保存密钥") }
        if self == .clear && required { throw APIError.serverMessage("启用的功能需要此密钥，请先停用后再清除") }
        if self == .replace && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (required || hasSaved) {
            throw APIError.serverMessage("请输入新密钥，或明确选择保留 / 清除")
        }
    }

    func payload(_ draft: String) -> String { self == .replace ? draft : "" }
}

struct NativeSecretEditor: View {
    let title: String
    let hasSaved: Bool
    @Binding var mode: NativeSecretMode
    @Binding var value: String
    var required = false
    @ObservedObject private var language = LanguageManager.shared
    @EnvironmentObject private var appearance: AppearanceController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: AppTheme.bodySize, weight: .medium))
                Spacer()
                Text(language.text(hasSaved ? "已配置" : "未配置", hasSaved ? "Configured" : "Not configured"))
                    .font(.system(size: AppTheme.secondarySize))
            }
            SelectMenu(options: NativeSecretMode.allCases.filter { ($0 != .keep || hasSaved) && ($0 != .clear || !required) }
                .map { SelectOption(id: $0.rawValue, title: $0.title) },
                selection: Binding(get: { mode.rawValue }, set: {
                    guard let raw = $0, let newMode = NativeSecretMode(rawValue: raw) else { return }
                    mode = newMode
                    value = ""
                }), width: 240, allowClear: false, searchable: false)
            if mode == .replace {
                AppTextField(text: $value, placeholder: language.text("输入新值", "Enter a new value"), secure: true)
            } else {
                Text(language.text(mode == .keep ? "保持服务器保存的值；不会读取或回填密钥。" : "保存后将清除服务器中的值。",
                                   mode == .keep ? "The saved value stays on the server; it is never read back." : "Saving clears the value on the server."))
                    .font(.system(size: AppTheme.secondarySize))
            }
        }
        .foregroundColor(AppTheme.textPrimary(appearance.isDarkEffective))
    }
}
