import SwiftUI

/// Full-window overlay: dimless hit area + right-aligned panels under the top bar.
/// Keeps dropdowns inside the app window (no system popover).
struct TopNavDropdownOverlay: View {
    @ObservedObject var chrome: TopNavChromeState
    @ObservedObject var header: HeaderViewModel
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var appearance: AppearanceController

    private var dark: Bool { appearance.isDarkEffective }

    /// Match MainShell top bar height
    private let topBarHeight: CGFloat = 56
    private let trailingPad: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // Click-catcher — closes any open menu
                if chrome.open != .none {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width, height: geo.size.height)
                        .onTapGesture { chrome.close() }
                }

                if chrome.open == .language {
                    languagePanel
                        .padding(.top, topBarHeight + 4)
                        .padding(.trailing, trailingPad + 120) // left of user widget
                        .transition(.opacity)
                }

                if chrome.open == .user {
                    UserDropdownPanel(
                        dark: dark,
                        username: session.username,
                        levelTitle: header.levelBadgeTitle,
                        level: header.levelBadgeLevel,
                        cloudProvider: session.cloudProvider,
                        onAsset: {
                            chrome.close()
                            header.openAssetAnalysis()
                        },
                        onCloud: { type, _ in
                            chrome.close()
                            // Instant switch — no success toast; UI already reflects selection.
                            session.setCloudProvider(type)
                        },
                        onAbout: {
                            chrome.close()
                            header.showAbout = true
                        },
                        onLogout: {
                            chrome.close()
                            Task { await session.logout() }
                        }
                    )
                    .padding(.top, topBarHeight + 4)
                    .padding(.trailing, trailingPad)
                    .shadow(color: Color.black.opacity(dark ? 0.45 : 0.18), radius: 16, y: 8)
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
        }
        .allowsHitTesting(chrome.open != .none)
    }

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("语言")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.45) : Color(hex: "6b7280"))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(AppLocale.allCases) { loc in
                Button(action: {
                    header.setLocale(loc)
                    chrome.close()
                }) {
                    HStack {
                        Text(loc.title)
                            .font(.system(size: 13))
                        Spacer()
                        if header.locale == loc {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.sidebarActive)
                        }
                    }
                    .foregroundColor(dark ? Color.white.opacity(0.9) : Color(hex: "111827"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.bottom, 8)
        .frame(width: 160, alignment: .leading)
        .background(dark ? Color(hex: "2a2f36") : Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(dark ? 0.45 : 0.18), radius: 16, y: 8)
    }
}
