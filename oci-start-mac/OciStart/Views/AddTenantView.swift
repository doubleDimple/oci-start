import SwiftUI
import AppKit

struct AddTenantView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss

    @State private var tenantId    = ""
    @State private var userName    = ""
    @State private var tenancyName = ""
    @State private var region      = ""
    @State private var keyFilePath: URL?
    @State private var keyFileData: Data?
    @State private var isSaving    = false
    @State private var errorText: String?

    private let regions = [
        "ap-tokyo-1","ap-osaka-1","ap-seoul-1","ap-singapore-1",
        "ap-sydney-1","ap-mumbai-1","us-ashburn-1","us-phoenix-1",
        "us-sanjose-1","ca-toronto-1","eu-frankfurt-1","eu-zurich-1",
        "eu-amsterdam-1","sa-saopaulo-1","me-jeddah-1","ap-chuncheon-1",
        "ap-melbourne-1","us-chicago-1"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("添加 OCI 租户")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: { dismiss.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Tenant info
                    GroupBox {
                        VStack(spacing: 12) {
                            formRow("Tenancy OCID") {
                                TextField("ocid1.tenancy.oc1...", text: $tenantId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            formRow("User OCID") {
                                TextField("ocid1.user.oc1...", text: $userName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            formRow("租户名称") {
                                TextField("用于显示的名称", text: $tenancyName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            formRow("区域") {
                                Picker("", selection: $region) {
                                    Text("选择区域…").tag("")
                                    ForEach(regions, id: \.self) { r in
                                        Text(r).tag(r)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                        .padding(4)
                    } label: {
                        Label("租户信息", systemImage: "person.badge.key")
                    }

                    // API Key file
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: keyFilePath == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                                    .foregroundColor(keyFilePath == nil ? .secondary : .green)
                                Text(keyFilePath?.lastPathComponent ?? "未选择私钥文件")
                                    .foregroundColor(keyFilePath == nil ? .secondary : .primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("选择文件") { pickKeyFile() }
                                    .buttonStyle(.bordered)
                            }
                            Text("OCI API 私钥文件（.pem 格式），本地读取后上传到服务端，不会外传。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    } label: {
                        Label("API 私钥", systemImage: "lock.doc")
                    }

                    if let err = errorText {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("取消") { dismiss.wrappedValue.dismiss() }
                    .keyboardShortcut(.escape)
                Button(isSaving ? "保存中…" : "保存") {
                    Task { await save() }
                }
                .buttonStyle(ProminentButton())
                .disabled(isSaving || !isFormValid)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 500)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !tenantId.isEmpty && !userName.isEmpty && !region.isEmpty && keyFileData != nil
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 OCI 私钥文件"
        panel.allowedFileTypes = ["pem", "key", "txt"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            keyFilePath = url
            keyFileData = try? Data(contentsOf: url)
        }
    }

    private func save() async {
        guard let keyData = keyFileData else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        guard let url = URL(string: "\(appState.serverURL)/tenants/save") else { return }

        // Build multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("tenantId",    value: tenantId)
        appendField("userName",    value: userName)
        appendField("tenancyName", value: tenancyName)
        appendField("region",      value: region)
        appendField("cloudType",   value: "1")

        // File field
        let fileName = keyFilePath?.lastPathComponent ?? "private.pem"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"keyFileStr\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(keyData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.compatData(for: req)
            let resp = try? JSONDecoder().decode(ActionResponse.self, from: data)
            if resp?.success == true {
                appState.showToast("租户添加成功")
                await appState.loadTenants()
                dismiss.wrappedValue.dismiss()
            } else {
                errorText = resp?.message ?? "保存失败，请检查参数"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
