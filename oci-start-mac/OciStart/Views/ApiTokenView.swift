import SwiftUI
import AppKit

struct ApiTokenView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFullToken = false
    @State private var showRevokeAlert = false

    private var status: ApiTokenStatus? { appState.apiTokenStatus }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Status card
                GroupBox(label: Label("Token 状态", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let s = status {
                            HStack {
                                Circle()
                                    .fill(s.enabled == true ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(s.enabled == true ? "已启用" : "未启用")
                                    .font(.callout)
                            }
                            if let token = s.token, !token.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Token").font(.caption.weight(.medium)).foregroundColor(.secondary)
                                    HStack {
                                        Text(showFullToken ? token : maskToken(token))
                                            .font(.system(.callout, design: .monospaced))
                                            .lineLimit(2)
                                        Button(action: { showFullToken.toggle() }) {
                                            Image(systemName: showFullToken ? "eye.slash" : "eye")
                                        }
                                        .buttonStyle(.plain)
                                        Button(action: { copyToken(token) }) {
                                            Image(systemName: "doc.on.doc")
                                        }
                                        .buttonStyle(.plain)
                                        .help("复制 Token")
                                    }
                                }
                            }
                            if let created = s.createdAt {
                                Text("创建时间：\(String(created.prefix(10)))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            Text("暂无 Token").foregroundColor(.secondary).font(.callout)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Actions
                GroupBox(label: Label("操作", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button("生成新 Token") {
                                Task { await appState.generateApiToken() }
                            }
                            .buttonStyle(ProminentButton())

                            Button("撤销 Token") {
                                showRevokeAlert = true
                            }
                            .foregroundColor(.red)
                            .disabled(status?.token == nil)
                        }

                        Text("生成后请妥善保管，Token 用于 Open API 调用，在请求头中传递 Authorization: Bearer <token>")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Usage example
                GroupBox(label: Label("使用示例", systemImage: "doc.text")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("curl 调用实例列表：").font(.caption.weight(.medium))
                        Text("""
curl -H "Authorization: Bearer <your-token>" \\
     \(appState.serverURL)/oci-start/open-api/v1/storage/buckets
""")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("API Token")
        .toolbar {
            ToolbarItem {
                Button(action: { Task { await appState.loadApiTokenStatus() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert(isPresented: $showRevokeAlert) {
            Alert(
                title: Text("确认撤销"),
                message: Text("Token 撤销后所有依赖该 Token 的 API 调用将失效。"),
                primaryButton: .destructive(Text("撤销")) {
                    Task { await appState.revokeApiToken() }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if appState.apiTokenStatus == nil { Task { await appState.loadApiTokenStatus() } }
        }
    }

    private func maskToken(_ token: String) -> String {
        guard token.count > 8 else { return "****" }
        return String(token.prefix(6)) + "****" + String(token.suffix(4))
    }

    private func copyToken(_ token: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        appState.showToast("Token 已复制")
    }
}
