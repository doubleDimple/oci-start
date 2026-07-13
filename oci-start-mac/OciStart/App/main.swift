import AppKit

let bundleId = "com.doubledimple.ocistart"

// Single instance: if already running, activate existing and exit this process.
// Prevents “second click looks like flash quit” and multiple Java backends.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    .filter { !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if let existing = others.first {
    existing.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    // Best-effort: ask existing instance to show window via distributed notification.
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.doubledimple.ocistart.showMainWindow"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Last-resort cleanup if terminate path is skipped (rare)
atexit {
    BackendController.shared.stop()
}

app.run()