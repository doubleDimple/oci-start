import SwiftUI

@main
struct OciStartApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var backend = BackendManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(backend)
                .frame(minWidth: 960, minHeight: 580)
                .onAppear {
                    Task { await backend.start() }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .onChange(of: scenePhase) { phase in
            if phase == .background { backend.stop() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("退出登录") {
                    Task { await appState.logout() }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!appState.isAuthenticated)
            }
        }
    }
}
