import AppKit
import SwiftUI

/// Created from `main.swift` (not `@main`) so NSApp.delegate is always set.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var showWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log("didFinishLaunching begin pid=\(ProcessInfo.processInfo.processIdentifier)")

        NSApp.setActivationPolicy(.regular)

        // Second-instance / Dock re-open signal
        showWindowObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.doubledimple.ocistart.showMainWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentMainWindow(reason: "distributed-show")
        }

        let appearance = AppearanceController.shared
        appearance.apply()
        MenuBuilder.install()

        let session = AppSession.shared
        let navigation = NavigationState.shared
        let backend = BackendController.shared

        let wc = MainWindowController(
            session: session,
            navigation: navigation,
            backend: backend,
            appearance: appearance
        )
        mainWindowController = wc
        presentMainWindow(reason: "launch")

        // Login first — do NOT auto-start embedded Java.
        // Backend starts only after user explicitly picks「本机使用」on the login page.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task {
                Self.log("await user deployment choice (no auto backend start); lastMode=\(session.deploymentMode.rawValue)")
                await session.bootstrap()
                Self.log("bootstrap isLoggedIn=\(session.isLoggedIn)")
            }
        }
    }

    /// Menu bar「退出 OCI Start」/ ⌘Q：先关页面，再停后端，最后允许进程退出。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.log("shouldTerminate — close UI first")
        // 1) Close / hide UI immediately so the user sees the app leave before Java teardown.
        if let window = mainWindowController?.window {
            window.orderOut(nil)
        }
        for w in NSApp.windows {
            w.orderOut(nil)
        }
        // Drop shell content so we are not painting while backend dies.
        mainWindowController = nil

        // 2) Stop backend off the main thread (stop() may sleep for SIGTERM grace).
        DispatchQueue.global(qos: .userInitiated).async {
            Self.log("shouldTerminate — stopping backend")
            BackendController.shared.stop()
            Self.log("shouldTerminate — backend stop done, reply terminate")
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Belt-and-suspenders if shouldTerminate path was skipped (force-quit edge cases).
        BackendController.shared.stop()
        Self.log("willTerminate")
        if let showWindowObserver = showWindowObserver {
            DistributedNotificationCenter.default().removeObserver(showWindowObserver)
        }
    }

    /// Never auto-quit when window list is empty — flash-quit root cause for users.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentMainWindow(reason: "reopen flag=\(flag)")
        return true
    }

    @objc func logoutAction(_ sender: Any?) {
        Task { await AppSession.shared.logout() }
    }

    @objc func refreshAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .ociReloadCurrentPage, object: nil)
    }

    @objc func cycleThemeAction(_ sender: Any?) {
        AppearanceController.shared.cycle()
    }

    @objc func toggleSidebarAction(_ sender: Any?) {
        NavigationState.shared.sidebarCollapsed.toggle()
    }

    @objc func navigateMenuAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? String,
              let nav = NavID(rawValue: raw) else { return }
        guard AppSession.shared.isLoggedIn else { return }
        NavigationState.shared.select(nav)
    }

    private func presentMainWindow(reason: String) {
        guard let wc = mainWindowController, let window = wc.window else {
            Self.log("presentMainWindow(\(reason)): no window")
            return
        }
        window.isReleasedWhenClosed = false
        wc.applyStandardFrame(force: true)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.log("presentMainWindow(\(reason)) frame=\(NSStringFromRect(window.frame)) windows=\(NSApp.windows.count)")
        // One settle pass only — avoid repeated setFrame during constraint cycles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            wc.applyStandardFrame(force: false)
            Self.log("presentMainWindow(\(reason)) settled frame=\(NSStringFromRect(window.frame))")
        }
    }

    static func log(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(msg)\n"
        fputs(line, stderr)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OciStart", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("launch.log")
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
