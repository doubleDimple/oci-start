import SwiftUI

/// Sidebar item 「OCI AI管理」— keeps Web models page + secondary AI chat entry.
/// Chat is NOT a sidebar item (Web sidebar.ftl has no AI chat entry).
struct AiModelsHubView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showChat = false
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("OCI AI管理")
                    .font(.headline)
                    .foregroundColor(AppTheme.text(scheme))
                Spacer()
                Button(action: { showChat = true }) {
                    Label("AI 对话", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(ProminentButton())
                Button(action: { reloadToken = UUID() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(AppTheme.muted(scheme))
                }
                .buttonStyle(.plain)
                .help("刷新配置页")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surface(scheme))

            Divider()

            OciWebView(url: pageURL)
                .id(reloadToken)
        }
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .navigationTitle("OCI AI管理")
        .sheet(isPresented: $showChat) {
            VStack(spacing: 0) {
                HStack {
                    Text("AI 对话").font(.title3.weight(.semibold))
                    Spacer()
                    Button(action: { showChat = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
                AiChatView()
                    .environmentObject(appState)
            }
            .frame(width: 900, height: 640)
        }
    }

    private var pageURL: URL {
        URL(string: "\(appState.serverURL)/system/ai/models") ?? URL(string: "about:blank")!
    }
}
