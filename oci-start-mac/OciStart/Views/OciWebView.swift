import SwiftUI
import WebKit
import AppKit

/// Embedded content page — injects Sa-Token (`satoken`) from shared cookie jar.
/// Used as transition for pages not yet natively rewritten.
struct OciWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        // default store so cookies can persist within the app session
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")

        injectCookies(into: config.websiteDataStore.httpCookieStore) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let current = wv.url?.absoluteString ?? ""
        let target = url.absoluteString
        guard current != target else { return }
        injectCookies(into: wv.configuration.websiteDataStore.httpCookieStore) {
            wv.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func injectCookies(into store: WKHTTPCookieStore, done: @escaping () -> Void) {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        // Prefer satoken + session cookies for this host
        let host = url.host
        let relevant = cookies.filter { c in
            if let host = host, let domain = c.domain as String? {
                let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
                if !(host == d || host.hasSuffix(".\(d)") || d == "localhost") {
                    // still allow exact host-less cookies
                    if c.domain != "localhost" && !c.domain.isEmpty && host != "localhost" {
                        return c.name == "satoken" || c.name.uppercased().contains("SESSION")
                    }
                }
            }
            return true
        }
        let group = DispatchGroup()
        for c in relevant {
            group.enter()
            store.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main, execute: done)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ wv: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open external http(s) targets that leave localhost in system browser
            if navigationAction.navigationType == .linkActivated,
               let u = navigationAction.request.url,
               let host = u.host,
               host != "localhost", host != "127.0.0.1" {
                NSWorkspace.shared.open(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ wv: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

/// Thin wrapper: full-window embedded page with a toolbar refresh button
struct EmbeddedPage: View {
    let title: String
    let path: String
    @EnvironmentObject var appState: AppState
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                    .foregroundColor(.secondary)
                Text("网页嵌入模式 · 复杂页暂用 Web 渲染")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            OciWebView(url: pageURL)
                .id(reloadToken)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem {
                Button(action: { reloadToken = UUID() }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button(action: openInBrowser) {
                    Label("浏览器打开", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private var pageURL: URL {
        URL(string: "\(appState.serverURL)\(path)") ?? URL(string: "about:blank")!
    }

    private func openInBrowser() {
        NSWorkspace.shared.open(pageURL)
    }
}

/// Sheet-modal embedded page with title bar and close button
struct EmbeddedPageSheet: View {
    let title: String
    let path: String
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) private var dismiss
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Button(action: { reloadToken = UUID() }) {
                    Image(systemName: "arrow.clockwise").foregroundColor(.secondary)
                }.buttonStyle(.plain).help("刷新")
                Button(action: { dismiss.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title3)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            OciWebView(url: pageURL).id(reloadToken)
        }
        .frame(width: 900, height: 640)
    }

    private var pageURL: URL {
        URL(string: "\(appState.serverURL)\(path)") ?? URL(string: "about:blank")!
    }
}
