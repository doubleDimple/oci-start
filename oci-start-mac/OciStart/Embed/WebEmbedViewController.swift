import AppKit
import WebKit

/// Embeds a backend FreeMarker page with full feature parity (modals, SSE, uploads).
/// Cookie session is mirrored from `HTTPCookieStorage` → `WKHTTPCookieStore`.
///
/// Use for complex Web pages (tenant management, etc.) until fully nativized.
final class WebEmbedViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {

    private let session: AppSession
    private let path: String
    private let query: [String: String]
    private let pageTitle: String

    private var webView: WKWebView!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var titleLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var emptyLabel: NSTextField!

    private var progressObs: NSKeyValueObservation?
    private var canGoBackObs: NSKeyValueObservation?
    private var canGoForwardObs: NSKeyValueObservation?
    private var titleObs: NSKeyValueObservation?
    private var loadGeneration = 0

    init(
        session: AppSession,
        path: String,
        query: [String: String] = [:],
        title: String
    ) {
        self.session = session
        self.path = path
        self.query = query
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressObs?.invalidate()
        canGoBackObs?.invalidate()
        canGoForwardObs?.invalidate()
        titleObs?.invalidate()
    }

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        root.wantsLayer = true
        root.autoresizingMask = [.width, .height]
        view = root

        let bar = makeToolbar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)

        let dark = AppearanceController.shared.isDarkEffective
        root.wantsLayer = true
        root.layer?.backgroundColor = Self.pageBgColor(dark: dark).cgColor

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.websiteDataStore = .default()
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Theme + Mac chrome CSS (AppTheme / AppInputStyle tokens) before first paint.
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebEmbedStyle.userScriptSource(dark: dark),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        // Also at end of document in case head is rewritten by late CSS.
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebEmbedStyle.userScriptSource(dark: dark),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            // no-op on 11
        }
        root.addSubview(wv)
        webView = wv

        let progress = NSProgressIndicator(frame: .zero)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(progress)
        progressBar = progress

        let empty = NSTextField(labelWithString: "")
        empty.isHidden = true
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize: 13)
        empty.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(empty)
        emptyLabel = empty

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),

            progress.topAnchor.constraint(equalTo: bar.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),

            wv.topAnchor.constraint(equalTo: progress.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24)
        ])
    }

    private func makeToolbar() -> NSView {
        let dark = AppearanceController.shared.isDarkEffective
        let bar = NSView()
        bar.wantsLayer = true
        // Match AppTheme sidebar / page header strip
        bar.layer?.backgroundColor = Self.toolbarBgColor(dark: dark).cgColor

        let border = CALayer()
        border.backgroundColor = Self.borderColor(dark: dark).cgColor
        border.frame = CGRect(x: 0, y: 0, width: 2000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        bar.layer?.addSublayer(border)

        let iconColor = Self.secondaryTextColor(dark: dark)

        func iconButton(_ systemName: String, action: Selector) -> NSButton {
            let b = NSButton(frame: .zero)
            b.bezelStyle = .recessed
            b.isBordered = false
            let img = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
            b.image = img
            b.contentTintColor = iconColor
            b.imagePosition = .imageOnly
            b.target = self
            b.action = action
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 32).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return b
        }

        backButton = iconButton("chevron.left", action: #selector(goBack))
        forwardButton = iconButton("chevron.right", action: #selector(goForward))
        reloadButton = iconButton("arrow.clockwise", action: #selector(reloadPage))

        titleLabel = NSTextField(labelWithString: pageTitle)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = Self.primaryTextColor(dark: dark)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let openBtn = NSButton(title: "浏览器打开", target: self, action: #selector(openInBrowser))
        openBtn.bezelStyle = .inline
        openBtn.isBordered = true
        openBtn.font = .systemFont(ofSize: 11, weight: .medium)
        openBtn.contentTintColor = Self.accentColor
        openBtn.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(backButton)
        bar.addSubview(forwardButton)
        bar.addSubview(reloadButton)
        bar.addSubview(titleLabel)
        bar.addSubview(openBtn)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            backButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openBtn.leadingAnchor, constant: -12),
            openBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            openBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        backButton.isEnabled = false
        forwardButton.isEnabled = false
        return bar
    }

    // MARK: - AppTheme → NSColor

    private static let accentColor = NSColor(srgbRed: 0x1a / 255, green: 0xbc / 255, blue: 0x9c / 255, alpha: 1)

    private static func pageBgColor(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0x1a / 255, green: 0x1d / 255, blue: 0x21 / 255, alpha: 1)
            : NSColor(srgbRed: 0xf0 / 255, green: 0xf4 / 255, blue: 0xf8 / 255, alpha: 1)
    }

    private static func toolbarBgColor(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0x1e / 255, green: 0x21 / 255, blue: 0x24 / 255, alpha: 0.92)
            : NSColor(srgbRed: 0xe4 / 255, green: 0xea / 255, blue: 0xf2 / 255, alpha: 0.95)
    }

    private static func borderColor(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0x38 / 255, green: 0x3c / 255, blue: 0x40 / 255, alpha: 1)
            : NSColor(srgbRed: 0xb8 / 255, green: 0xc8 / 255, blue: 0xd8 / 255, alpha: 1)
    }

    private static func primaryTextColor(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0xcd / 255, green: 0xd9 / 255, blue: 0xe5 / 255, alpha: 1)
            : NSColor(srgbRed: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255, alpha: 1)
    }

    private static func secondaryTextColor(dark: Bool) -> NSColor {
        dark
            ? NSColor(srgbRed: 0xa9 / 255, green: 0xb7 / 255, blue: 0xc6 / 255, alpha: 1)
            : NSColor(srgbRed: 0x37 / 255, green: 0x4a / 255, blue: 0x61 / 255, alpha: 1)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeWebView()
        startLoad()
    }

    private func observeWebView() {
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let p = wv.estimatedProgress
                self.progressBar.doubleValue = p
                self.progressBar.isHidden = p >= 1.0 || p <= 0
            }
        }
        canGoBackObs = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.backButton.isEnabled = wv.canGoBack }
        }
        canGoForwardObs = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.forwardButton.isEnabled = wv.canGoForward }
        }
        titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let t = (wv.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    self.titleLabel.stringValue = t
                }
            }
        }
    }

    // MARK: - Load

    private func startLoad() {
        loadGeneration += 1
        let gen = loadGeneration
        emptyLabel.isHidden = true
        progressBar.isHidden = false
        progressBar.doubleValue = 0.05

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.syncCookies()
                guard gen == self.loadGeneration else { return }
                let url = try APIClient.shared.makeURL(self.session.serverURL, path: self.path, query: self.query)
                await MainActor.run {
                    guard gen == self.loadGeneration else { return }
                    self.webView.load(URLRequest(url: url))
                }
            } catch {
                await MainActor.run {
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    /// Mirror URLSession cookies into the WebView so satoken session works.
    private func syncCookies() async throws {
        guard let base = URL(string: session.serverURL), let host = base.host else {
            throw APIError.invalidURL
        }
        let all = HTTPCookieStorage.shared.cookies ?? []
        // Prefer host-matching cookies; always include satoken-like names for this host.
        let relevant = all.filter { cookie in
            let d = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let hostMatch = host == d
                || host.hasSuffix(".\(d)")
                || d.hasSuffix(host)
                || cookie.domain == host
                || cookie.domain == ".\(host)"
                || cookie.domain == "localhost"
                || host == "127.0.0.1" && (d == "localhost" || d == "127.0.0.1")
            if !hostMatch { return false }
            return true
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in relevant {
            await setCookie(cookie, on: store)
            // Some backends set Domain without port; also inject a host-only copy for WKWebView.
            if cookie.domain != host,
               let copy = HTTPCookie(properties: [
                .name: cookie.name,
                .value: cookie.value,
                .domain: host,
                .path: cookie.path.isEmpty ? "/" : cookie.path,
                .secure: cookie.isSecure ? "TRUE" : "FALSE",
                .expires: cookie.expiresDate as Any
               ].compactMapValues { $0 }) {
                await setCookie(copy, on: store)
            }
        }
    }

    private func setCookie(_ cookie: HTTPCookie, on store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) {
                cont.resume()
            }
        }
    }

    private func showError(_ message: String) {
        emptyLabel.stringValue = "页面加载失败\n\(message)"
        emptyLabel.isHidden = false
        progressBar.isHidden = true
    }

    // MARK: - Actions

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadPage() {
        if webView.url != nil {
            webView.reload()
        } else {
            startLoad()
        }
    }

    @objc private func openInBrowser() {
        let url = webView.url
            ?? (try? APIClient.shared.makeURL(session.serverURL, path: path, query: query))
        if let url = url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Downloads (export JSON etc.)

    private func saveDownload(from url: URL, suggestedName: String?) {
        Task {
            do {
                try await syncCookies()
                var req = URLRequest(url: url)
                req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
                let (data, response) = try await APIClient.shared.data(for: req)
                let name: String = {
                    if let suggestedName = suggestedName, !suggestedName.isEmpty { return suggestedName }
                    if let http = response as? HTTPURLResponse,
                       let cd = http.value(forHTTPHeaderField: "Content-Disposition"),
                       let fn = Self.filename(fromContentDisposition: cd) {
                        return fn
                    }
                    return url.lastPathComponent.isEmpty ? "download.bin" : url.lastPathComponent
                }()
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = name
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let dest = panel.url {
                        do {
                            try data.write(to: dest, options: .atomic)
                        } catch {
                            AppAlert.error(message: error.localizedDescription)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    AppAlert.error(message: error.localizedDescription)
                }
            }
        }
    }

    private static func filename(fromContentDisposition cd: String) -> String? {
        // filename="x.json" or filename*=UTF-8''x.json
        if let range = cd.range(of: "filename\\*?=", options: .regularExpression) {
            var rest = String(cd[range.upperBound...])
            if rest.lowercased().hasPrefix("utf-8''") {
                rest = String(rest.dropFirst(7))
                return rest.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
            }
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
            if rest.hasPrefix("\"") { rest = String(rest.dropFirst()) }
            if rest.hasSuffix("\"") { rest = String(rest.dropLast()) }
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        emptyLabel.isHidden = true
        progressBar.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressBar.isHidden = true
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        // Re-sync cookies after first paint (login may have refreshed satoken mid-session).
        Task { try? await syncCookies() }
        // Re-apply Mac chrome CSS if SPA/fragment navigations stripped our style tag.
        let dark = AppearanceController.shared.isDarkEffective
        webView.evaluateJavaScript(WebEmbedStyle.userScriptSource(dark: dark), completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progressBar.isHidden = true
        // Ignore cancellation
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        showError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        progressBar.isHidden = true
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        showError(error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Keep same-origin navigations in-app (list → addSpeed → bootPage → …)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url else {
            decisionHandler(.allow)
            return
        }
        let cd = response.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let mime = response.mimeType ?? ""
        let isAttachment = cd.localizedCaseInsensitiveContains("attachment")
            || cd.localizedCaseInsensitiveContains("filename")
        let isDownloadMime = mime.contains("application/octet-stream")
            || mime.contains("application/json") && isAttachment
            || mime.contains("application/zip")

        if isAttachment || isDownloadMime, !navigationResponse.canShowMIMEType {
            decisionHandler(.cancel)
            let name = Self.filename(fromContentDisposition: cd)
            saveDownload(from: url, suggestedName: name)
            return
        }
        // Explicit export endpoints often stream JSON with attachment disposition
        if isAttachment {
            decisionHandler(.cancel)
            let name = Self.filename(fromContentDisposition: cd)
            saveDownload(from: url, suggestedName: name)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate (window.open → same webview)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        AppAlert.info(title: pageTitle, message: message)
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let ok = AppAlert.confirm(title: pageTitle, message: message, confirmTitle: "确定", cancelTitle: "取消")
        completionHandler(ok)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = pageTitle
        alert.informativeText = prompt
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        let result = alert.runModal()
        completionHandler(result == .alertFirstButtonReturn ? field.stringValue : nil)
    }
}
