import SwiftUI
import AppKit

/// Ensures Java backend stops when the app really quits (not when just backgrounded).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        BackendManager.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct OciStartApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var backend = BackendManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(backend)
                .frame(minWidth: 1020, minHeight: 640)
                .onAppear {
                    // Default comfortable window size (Big Sur+)
                    if let window = NSApplication.shared.windows.first {
                        if window.frame.width < 1100 || window.frame.height < 700 {
                            window.setContentSize(NSSize(width: 1280, height: 800))
                            window.center()
                        }
                    }
                    Task { await backend.start() }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        // NOTE: Do NOT stop backend on scenePhase.background — switching apps would kill Java.
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("退出登录") {
                    Task { await appState.logout() }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!appState.isAuthenticated)
            }
            CommandGroup(after: .toolbar) {
                Button("刷新当前数据") {
                    Task {
                        await appState.loadDashboard()
                        await appState.loadInstances()
                        await appState.loadTenants()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appState.isAuthenticated)
            }
        }
    }
}
