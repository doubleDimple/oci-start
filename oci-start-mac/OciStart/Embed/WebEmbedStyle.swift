import Foundation

/// Injected into WKWebView so embedded FreeMarker pages match Mac `AppTheme` / Common chrome.
enum WebEmbedStyle {

    /// CSS + bootstrap JS: theme tokens + soft Mac-native controls (radius 12, accent #1abc9c).
    static func userScriptSource(dark: Bool) -> String {
        let theme = dark ? "dark" : "light"
        // Tokens aligned with AppTheme + AppInputStyle + RegionsTheme
        let css: String
        if dark {
            css = """
            :root, html[data-theme="dark"], html {
              --top-nav-bg: #1f1f1f !important;
              --sidebar-bg: #1e2124 !important;
              --sidebar-hover: #292d30 !important;
              --sidebar-active: #1abc9c !important;
              --sidebar-text: #a9b7c6 !important;
              --main-bg: #1a1d21 !important;
              --surface: #22262b !important;
              --surface-2: #292d32 !important;
              --text-primary: #cdd9e5 !important;
              --text-secondary: #768390 !important;
              --text-light: #ffffff !important;
              --accent-blue: #4d9eff !important;
              --accent-green: #1abc9c !important;
              --accent-red: #f85149 !important;
              --accent-orange: #f78166 !important;
              --hover-bg: #2d3138 !important;
              --card-border: #31363d !important;
              --border-color: #383c40 !important;
              --shadow-color: rgba(0,0,0,0.35) !important;
              --mac-input-fill: #292d32 !important;
              --mac-input-border: #31363d !important;
              --mac-focus: #4d9eff !important;
            }
            """
        } else {
            css = """
            :root, html[data-theme="light"], html {
              --top-nav-bg: #d0dae6 !important;
              --sidebar-bg: #e4eaf2 !important;
              --sidebar-hover: #d6dfe9 !important;
              --sidebar-active: #1abc9c !important;
              --sidebar-text: #374a61 !important;
              --main-bg: #f0f4f8 !important;
              --surface: #ffffff !important;
              --surface-2: #f8fafc !important;
              --text-primary: #111827 !important;
              --text-secondary: #4b5563 !important;
              --text-light: #ffffff !important;
              --accent-blue: #3b82f6 !important;
              --accent-green: #1abc9c !important;
              --accent-red: #ef4444 !important;
              --accent-orange: #f97316 !important;
              --hover-bg: #f1f5f9 !important;
              --card-border: #e8ecf0 !important;
              --border-color: #b8c8d8 !important;
              --shadow-color: rgba(15,23,42,0.08) !important;
              --mac-input-fill: #f8f9fa !important;
              --mac-input-border: #e4e7ed !important;
              --mac-focus: #42b983 !important;
            }
            """
        }

        let layout = """
        /* Embed: content fills Mac split detail pane */
        html, body {
          background: var(--main-bg) !important;
          color: var(--text-primary) !important;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif !important;
          font-size: 13px !important;
          -webkit-font-smoothing: antialiased;
        }
        .layout { padding-top: 0 !important; min-height: 100vh; background: var(--main-bg) !important; }
        .main-content {
          margin-left: 0 !important;
          padding: 16px 20px 24px !important;
          background: var(--main-bg) !important;
          max-width: 100% !important;
        }
        .page-card {
          background: var(--surface-2) !important;
          border: 1px solid var(--card-border) !important;
          border-radius: 12px !important;
          box-shadow: 0 2px 12px var(--shadow-color) !important;
          padding: 18px 20px !important;
        }
        .page-header {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 12px;
          padding-bottom: 12px;
          margin-bottom: 12px;
          border-bottom: 1px solid var(--card-border) !important;
        }
        .page-title {
          font-size: 18px !important;
          font-weight: 600 !important;
          color: var(--text-primary) !important;
          letter-spacing: -0.2px;
        }
        .page-title i { color: var(--sidebar-active) !important; margin-right: 8px; }

        /* Buttons → AppButton-ish */
        .btn, button.btn, a.btn {
          border-radius: 8px !important;
          font-size: 12px !important;
          font-weight: 600 !important;
          padding: 7px 12px !important;
          border: none !important;
          transition: background .15s ease, opacity .15s ease !important;
        }
        .btn-primary, .btn.btn-primary {
          background: var(--sidebar-active) !important;
          color: #fff !important;
        }
        .btn-primary:hover { filter: brightness(1.08); }
        .btn-success, .btn.btn-success {
          background: var(--sidebar-active) !important;
          color: #fff !important;
        }
        .btn-secondary, .btn.btn-secondary, .btn:not(.btn-primary):not(.btn-success):not(.btn-danger):not(.btn-warning) {
          background: transparent !important;
          color: var(--text-primary) !important;
          border: 1px solid var(--card-border) !important;
        }
        .btn-danger, .btn.btn-danger {
          background: var(--accent-red) !important;
          color: #fff !important;
        }
        .btn-warning {
          background: var(--accent-orange) !important;
          color: #fff !important;
        }
        .btn-boot {
          display: inline-flex !important;
          align-items: center !important;
          gap: 4px !important;
          background: var(--sidebar-active) !important;
          color: #fff !important;
          border-radius: 8px !important;
          padding: 4px 10px !important;
          font-size: 11px !important;
          font-weight: 600 !important;
          text-decoration: none !important;
        }

        /* Inputs → AppInputStyle */
        input[type="text"], input[type="search"], input[type="email"], input[type="number"],
        input[type="password"], input:not([type]), select, textarea, .form-control, .search-input {
          background: var(--mac-input-fill) !important;
          border: 1px solid var(--mac-input-border) !important;
          border-radius: 12px !important;
          color: var(--text-primary) !important;
          font-size: 13px !important;
          padding: 8px 12px !important;
          outline: none !important;
          box-shadow: none !important;
          min-height: 36px;
        }
        input:focus, select:focus, textarea:focus, .form-control:focus, .search-input:focus {
          border-color: var(--mac-focus) !important;
          box-shadow: 0 0 0 3px rgba(26, 188, 156, 0.18) !important;
        }
        .search-input-group .search-btn {
          border-radius: 0 12px 12px 0 !important;
          background: var(--sidebar-active) !important;
        }
        .search-form .search-input {
          border-radius: 12px 0 0 12px !important;
        }

        /* Table */
        .table-view, .table-responsive {
          border: 1px solid var(--card-border) !important;
          border-radius: 12px !important;
          overflow: hidden;
          background: var(--surface) !important;
        }
        table.table {
          width: 100% !important;
          border-collapse: collapse !important;
          background: transparent !important;
        }
        table.table thead th {
          background: var(--surface-2) !important;
          color: var(--text-secondary) !important;
          font-size: 11px !important;
          font-weight: 600 !important;
          padding: 10px 8px !important;
          border-bottom: 1px solid var(--card-border) !important;
          text-align: left !important;
        }
        table.table tbody td {
          padding: 10px 8px !important;
          border-bottom: 1px solid var(--card-border) !important;
          font-size: 12px !important;
          color: var(--text-primary) !important;
          vertical-align: middle !important;
        }
        table.table tbody tr:hover td {
          background: var(--hover-bg) !important;
        }
        .cell-edit-link, a.cell-edit-link, .account-type-link {
          color: var(--sidebar-active) !important;
          text-decoration: none !important;
        }
        .status-badge, .days-chip, .home-region-badge {
          border-radius: 10px !important;
          font-size: 11px !important;
          font-weight: 600 !important;
          padding: 3px 8px !important;
        }
        .status-running {
          background: rgba(26, 188, 156, 0.16) !important;
          color: var(--accent-green) !important;
        }
        .status-idle {
          background: rgba(118, 131, 144, 0.16) !important;
          color: var(--text-secondary) !important;
        }

        /* Dropdown actions */
        .dropdown-toggle.btn {
          background: transparent !important;
          border: 1px solid var(--card-border) !important;
          border-radius: 8px !important;
          color: var(--text-secondary) !important;
        }
        .dropdown-panel, .dropdown-menu {
          background: var(--surface) !important;
          border: 1px solid var(--card-border) !important;
          border-radius: 10px !important;
          box-shadow: 0 8px 28px var(--shadow-color) !important;
          overflow: hidden;
        }
        .dropdown-item {
          color: var(--text-primary) !important;
          font-size: 12px !important;
          padding: 8px 12px !important;
        }
        .dropdown-item:hover {
          background: var(--hover-bg) !important;
        }

        /* Modals */
        .modal-overlay {
          background: rgba(0,0,0,0.45) !important;
          backdrop-filter: blur(4px);
        }
        .modal-container, .modal-content, .swal2-popup {
          background: var(--surface) !important;
          color: var(--text-primary) !important;
          border: 1px solid var(--card-border) !important;
          border-radius: 12px !important;
          box-shadow: 0 16px 48px var(--shadow-color) !important;
        }
        .modal-header, .modal-title, .swal2-title {
          color: var(--text-primary) !important;
          font-weight: 600 !important;
        }
        .user-management-tabs {
          background: var(--surface-2) !important;
          border-radius: 10px !important;
          padding: 4px !important;
        }
        .user-tab {
          border-radius: 8px !important;
          border: none !important;
          background: transparent !important;
          color: var(--text-secondary) !important;
          font-size: 12px !important;
          font-weight: 600 !important;
          padding: 8px 14px !important;
        }
        .user-tab.active {
          background: var(--sidebar-active) !important;
          color: #fff !important;
        }

        /* Pagination */
        .pagination, .pagination-bar, .page-pagination {
          border-top: 1px solid var(--card-border) !important;
          padding-top: 10px !important;
          margin-top: 8px !important;
        }
        .pagination a, .pagination button, .pagination span {
          border-radius: 8px !important;
          font-size: 12px !important;
        }

        /* Name spoiler / chips */
        .name-spoiler { cursor: pointer; color: var(--text-primary) !important; }
        .search-results-info {
          background: rgba(26, 188, 156, 0.12) !important;
          border: 1px solid rgba(26, 188, 156, 0.28) !important;
          border-radius: 10px !important;
          padding: 10px 12px !important;
          color: var(--text-secondary) !important;
        }

        /* Custom select if present */
        .custom-select-trigger, .cs-trigger {
          border-radius: 12px !important;
          background: var(--mac-input-fill) !important;
          border: 1px solid var(--mac-input-border) !important;
        }
        """

        // Escape for JS string in template - we inject via style element, not template literal issues
        let fullCSS = (css + layout)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")

        return """
        (function(){
          try {
            localStorage.setItem('oci_theme', '\(theme)');
            document.documentElement.dataset.theme = '\(theme)';
          } catch (e) {}
          function inject() {
            if (document.getElementById('mac-embed-style')) return;
            var s = document.createElement('style');
            s.id = 'mac-embed-style';
            s.textContent = `\(fullCSS)`;
            (document.head || document.documentElement).appendChild(s);
          }
          inject();
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', inject);
          }
        })();
        """
    }
}
