import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var backend: BackendManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch backend.state {
            case .starting:
                StartupView()
            case .failed(let msg):
                StartupFailedView(message: msg)
            case .ready:
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBg(scheme).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: backendStateKey)
    }

    private var backendStateKey: String {
        switch backend.state {
        case .starting: return "starting"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            if appState.isAuthenticated {
                MainView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            Task { await appState.checkSessionPublic() }
        }
        .alert(isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Alert(
                title: Text("错误"),
                message: Text(appState.errorMessage ?? ""),
                dismissButton: .default(Text("确定")) {
                    appState.errorMessage = nil
                }
            )
        }
    }
}

// MARK: - Startup splash

struct StartupView: View {
    @EnvironmentObject var backend: BackendManager
    @Environment(\.colorScheme) private var scheme
    @State private var dots = ""
    @State private var timer: Timer?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent(scheme).opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.08 : 0.95)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.accent(scheme))
            }

            Text("OCI Start")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.text(scheme))

            ProgressView()
                .scaleEffect(0.9)

            Text("正在启动后端服务\(dots)")
                .font(.callout)
                .foregroundColor(AppTheme.muted(scheme))
                .frame(width: 220, alignment: .center)

            if !backend.logBuffer.isEmpty {
                ScrollView {
                    Text(backend.logBuffer.suffix(10).joined())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.muted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 500, height: 90)
                .padding(8)
                .background(AppTheme.surface(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(scheme), lineWidth: 1)
                )
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startDots()
            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func startDots() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
            dots = dots.count < 3 ? dots + "." : ""
        }
    }
}

// MARK: - Startup failed

struct StartupFailedView: View {
    let message: String
    @EnvironmentObject var backend: BackendManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.danger)

            Text("后端服务启动失败")
                .font(.title2.weight(.semibold))
                .foregroundColor(AppTheme.text(scheme))

            Text(message)
                .font(.callout)
                .foregroundColor(AppTheme.muted(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if !backend.logBuffer.isEmpty {
                ScrollView {
                    Text(backend.logBuffer.suffix(40).joined())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.muted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(width: 500, height: 140)
                .background(AppTheme.surface(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(scheme), lineWidth: 1)
                )
                .cornerRadius(8)
            }

            HStack(spacing: 12) {
                Button("复制日志") {
                    let text = backend.logBuffer.joined()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.muted(scheme))

                Button("重新启动") {
                    Task { await backend.restart() }
                }
                .buttonStyle(ProminentButton())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
