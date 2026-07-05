import SwiftUI
import AppKit

struct MfaBackupView: View {
    @EnvironmentObject var appState: AppState

    @State private var keyName   = ""
    @State private var secretKey = ""
    @State private var qrUrl     = ""
    @State private var isSaving  = false
    @State private var generatedCodes: [OtpEntry] = []
    @State private var generateSecrets = ""
    @State private var isGenerating = false
    @State private var showAddSheet = false

    struct OtpEntry: Identifiable {
        let id = UUID()
        let name: String
        let code: String
    }

    var body: some View {
        HSplitView {
            // Left: Web-embedded key list
            VStack(spacing: 0) {
                HStack {
                    Text("OTP 密钥列表")
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Spacer()
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 16)
                }
                Divider()
                OciWebView(url: mfaPageURL)
            }
            .frame(minWidth: 360)

            // Right: Code generator
            codeGeneratorPanel
                .frame(minWidth: 280, maxWidth: 320)
        }
        .navigationTitle("MFA 备份")
        .sheet(isPresented: $showAddSheet) {
            AddOtpKeySheet()
                .environmentObject(appState)
        }
    }

    private var mfaPageURL: URL {
        URL(string: "\(appState.serverURL)/mfa/page") ?? URL(string: "about:blank")!
    }

    // MARK: - Code Generator

    private var codeGeneratorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("生成 OTP 验证码")
                .font(.headline)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输入 Secret Key（每行一个）")
                            .font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $generateSecrets)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 80, maxHeight: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    Button(isGenerating ? "生成中…" : "生成验证码") {
                        Task { await generateCodes() }
                    }
                    .buttonStyle(ProminentButton())
                    .disabled(isGenerating || generateSecrets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !generatedCodes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("验证码（30秒有效）")
                                .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                            ForEach(generatedCodes) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(entry.code)
                                            .font(.system(.title3, design: .monospaced).weight(.bold))
                                            .foregroundColor(.accentColor)
                                    }
                                    Spacer()
                                    Button(action: { copyCode(entry.code) }) {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    .help("复制验证码")
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func generateCodes() async {
        let keys = generateSecrets
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        isGenerating = true
        defer { isGenerating = false }

        do {
            let url = try appState.network.makeURL("\(appState.serverURL)/generate-otp-batch")
            struct BatchReq: Encodable { let secretKeys: [String] }
            struct BatchResp: Decodable { let otpCode: String?; let keyName: String? }
            let results: [BatchResp] = try await appState.network.postJSON(url, body: BatchReq(secretKeys: keys))
            generatedCodes = results.enumerated().map { i, r in
                OtpEntry(name: r.keyName ?? "Key \(i+1)", code: r.otpCode ?? "——")
            }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        appState.showToast("验证码已复制")
    }
}

// MARK: - Add OTP Key Sheet

struct AddOtpKeySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss

    @State private var keyName   = ""
    @State private var secretKey = ""
    @State private var qrUrl     = ""
    @State private var isSaving  = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("添加 OTP 密钥")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: { dismiss.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            Form {
                Section {
                    TextField("密钥名称", text: $keyName)
                    TextField("Secret Key（Base32）", text: $secretKey)
                        .font(.system(.body, design: .monospaced))
                    TextField("QR 图片 URL（选填）", text: $qrUrl)
                }
            }
            .padding(.horizontal, 4)

            if let err = errorText {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red).font(.caption)
                    .padding(.horizontal, 20)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss.wrappedValue.dismiss() }.keyboardShortcut(.escape)
                Button(isSaving ? "保存中…" : "保存") { Task { await save() } }
                    .buttonStyle(ProminentButton())
                    .disabled(isSaving || keyName.isEmpty || secretKey.isEmpty)
                    .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 400, height: 260)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let url = URL(string: "\(appState.serverURL)/save-secret") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "keyName",   value: keyName),
            URLQueryItem(name: "secretKey", value: secretKey),
            URLQueryItem(name: "qrUrl",     value: qrUrl)
        ]
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        do {
            _ = try await URLSession.shared.compatData(for: req)
            appState.showToast("密钥已保存")
            dismiss.wrappedValue.dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

