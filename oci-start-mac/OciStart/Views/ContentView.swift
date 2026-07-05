import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var backend: BackendManager

    var body: some View {
        switch backend.state {
        case .starting:
            StartupView()
        case .failed(let msg):
            StartupFailedView(message: msg)
        case .ready:
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            if appState.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            // Trigger session check only after backend is ready
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
    @State private var dots = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("OCI Start")
                .font(.largeTitle.weight(.bold))

            ProgressView()
                .scaleEffect(0.9)

            Text("正在启动后端服务\(dots)")
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .center)

            if !backend.logBuffer.isEmpty {
                ScrollView {
                    Text(backend.logBuffer.suffix(8).joined())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 480, height: 80)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .frame(width: 560, height: 360)
        .onAppear { startDots() }
        .onDisappear { timer?.invalidate() }
    }

    private func startDots() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            dots = dots.count < 3 ? dots + "." : ""
        }
    }
}

// MARK: - Startup failed

struct StartupFailedView: View {
    let message: String
    @EnvironmentObject var backend: BackendManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("后端服务启动失败")
                .font(.title2.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if !backend.logBuffer.isEmpty {
                ScrollView {
                    Text(backend.logBuffer.joined())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(width: 480, height: 120)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }

            Button("重新启动") {
                Task { await backend.restart() }
            }
            .buttonStyle(ProminentButton())
        }
        .frame(width: 560, height: 420)
    }
}
