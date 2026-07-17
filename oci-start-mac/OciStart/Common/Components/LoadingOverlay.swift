import Foundation
import Combine
import SwiftUI
import AppKit

// MARK: - Global native loading HUD

/// Window-level spinner: show while an operation runs, hide when it ends.
/// Prefer this over success/info text toasts for action feedback.
final class LoadingHUD: ObservableObject {
    static let shared = LoadingHUD()

    @Published private(set) var isVisible = false
    private var depth = 0

    private init() {}

    func begin() {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.depth += 1
            self.isVisible = true
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func end() {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.depth = max(0, self.depth - 1)
            if self.depth == 0 {
                self.isVisible = false
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Show spinner for the duration of `work`, then hide (even on throw).
    func during<T>(_ work: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await work()
    }
}

/// Centered native `ProgressView` spinner (no text). Host once in the main shell.
struct LoadingHost: View {
    @ObservedObject var hud: LoadingHUD = .shared

    var body: some View {
        ZStack {
            if hud.isVisible {
                Color.black.opacity(0.12)
                    .edgesIgnoringSafeArea(.all)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.15)
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 4)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hud.isVisible)
        .allowsHitTesting(hud.isVisible)
    }
}

// MARK: - Page-local loading

struct PageLoadingView: View {
    var message: String = "加载中…"

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.9)
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    /// 保留参数兼容调用方；页内 loading 仅展示原生转圈，不画文案/边框。
    var message: String = ""

    func body(content: Content) -> some View {
        ZStack {
            content
            if isLoading {
                // 轻微遮罩拦截点击，不出现卡片边框
                Color.black.opacity(0.08)
                    .edgesIgnoringSafeArea(.all)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.1)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isLoading)
    }
}
