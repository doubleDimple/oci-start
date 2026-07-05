import SwiftUI
import WebKit

/// Generic embedded web page — shares session cookies from URLSession.shared
struct OciWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        // Use non-persistent store so we can inject cookies manually
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator

        let store = config.websiteDataStore.httpCookieStore
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let group = DispatchGroup()
        cookies.forEach { c in
            group.enter()
            store.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main) { wv.load(URLRequest(url: url)) }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
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
        OciWebView(url: pageURL)
            .id(reloadToken)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem {
                    Button(action: { reloadToken = UUID() }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    private var pageURL: URL {
        URL(string: "\(appState.serverURL)\(path)") ?? URL(string: "about:blank")!
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
