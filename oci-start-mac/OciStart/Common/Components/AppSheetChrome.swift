import SwiftUI

// MARK: - Web modal tokens (`tenant-list.css` / `add_boot.css`)

/// Color tokens aligned with Web tenant modals (`--surface`, `--text-primary`, …).
enum AppSheetSurface {
    static func surface(_ dark: Bool) -> Color {
        dark ? Color(hex: "22262b") : Color.white
    }

    static func surface2(_ dark: Bool) -> Color {
        dark ? Color(hex: "292d32") : Color(hex: "f8fafc")
    }

    static func panelBg(_ dark: Bool) -> Color {
        dark ? Color(hex: "2d3138") : Color(hex: "f1f5f9") // --hover-bg
    }

    static func rowHover(_ dark: Bool) -> Color {
        panelBg(dark)
    }

    static func primaryText(_ dark: Bool) -> Color {
        dark ? Color(hex: "cdd9e5") : Color(hex: "1a202c")
    }

    static func mutedText(_ dark: Bool) -> Color {
        dark ? Color(hex: "768390") : Color(hex: "64748b")
    }

    static func border(_ dark: Bool) -> Color {
        dark ? Color(hex: "31363d") : Color(hex: "dde3ec")
    }

    static func cardBg(_ dark: Bool) -> Color { surface(dark) }

    static func accentBlue(_ dark: Bool) -> Color {
        dark ? Color(hex: "4d9eff") : Color(hex: "2563eb")
    }

    static func accentGreen(_ dark: Bool) -> Color {
        dark ? Color(hex: "3fb950") : Color(hex: "16a34a")
    }

    static func accentRed(_ dark: Bool) -> Color {
        dark ? Color(hex: "ff6b6b") : Color(hex: "dc2626")
    }

    static func accentOrange(_ dark: Bool) -> Color {
        dark ? Color(hex: "f78166") : Color(hex: "ea580c")
    }
}

// MARK: - Modal shell (Web `.modal-overlay` + `.modal-container`)

/// Unified modal shell for SwiftUI `.sheet`, matching Web:
/// `background: var(--surface); padding: 24px; border-radius: 16px; border: 1px solid var(--card-border)`.
struct AppSheetChrome<Content: View, Footer: View>: View {
    let title: String
    var systemImage: String? = nil
    var width: CGFloat = 520
    var height: CGFloat = 480
    var fixedSize: Bool = false
    var showClose: Bool = true
    var onClose: (() -> Void)? = nil
    let footer: Footer
    let content: Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    init(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = 520,
        height: CGFloat = 480,
        fixedSize: Bool = false,
        showClose: Bool = true,
        onClose: (() -> Void)? = nil,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.fixedSize = fixedSize
        self.showClose = showClose
        self.onClose = onClose
        self.footer = footer()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footerBar
        }
        .frame(
            minWidth: width,
            idealWidth: width,
            maxWidth: fixedSize ? width : width + 40,
            minHeight: height,
            idealHeight: height,
            maxHeight: fixedSize ? height : height + 40
        )
        .background(AppSheetSurface.surface(dark))
        .preferredColorScheme(dark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.sidebarActive)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppSheetSurface.primaryText(dark))
                .lineLimit(2)
            Spacer(minLength: 8)
            if showClose {
                Button(action: close) {
                    Text("×")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(AppSheetSurface.mutedText(dark))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("关闭")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .overlay(
            Rectangle()
                .fill(AppSheetSurface.border(dark))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .overlay(
            Rectangle()
                .fill(AppSheetSurface.border(dark))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func close() {
        if let onClose = onClose {
            onClose()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Tabs (Web `.user-management-tabs` / `.user-tab`)

/// Flat tabs: hover-bg track, active = surface + accent-blue (not filled green).
struct AppSheetTabBar: View {
    let titles: [String]
    let selectedIndex: Int
    var onSelect: (Int) -> Void

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { idx, title in
                let selected = selectedIndex == idx
                Button(action: { onSelect(idx) }) {
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .foregroundColor(
                            selected
                                ? AppSheetSurface.accentBlue(dark)
                                : AppSheetSurface.mutedText(dark)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selected ? AppSheetSurface.surface(dark) : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(AppSheetSurface.panelBg(dark))
        .cornerRadius(2)
    }
}

// MARK: - Table (Web `.table` inside modals)

struct AppSheetTableHeader: View {
    let columns: [(title: String, width: CGFloat?)]

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                Text(col.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppSheetSurface.mutedText(dark))
                    .lineLimit(1)
                    .frame(width: col.width, alignment: .leading)
                    .frame(maxWidth: col.width == nil ? .infinity : nil, alignment: .leading)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 10)
        .background(AppSheetSurface.panelBg(dark))
        .overlay(
            Rectangle()
                .fill(AppSheetSurface.border(dark))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct AppSheetTableRow<Content: View>: View {
    var striped: Bool = false
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        content()
            .padding(.vertical, 10)
            .background(striped ? AppSheetSurface.panelBg(dark).opacity(0.55) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(AppSheetSurface.border(dark).opacity(0.7))
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

/// Bordered table shell matching Web `.table-view`.
struct AppSheetTableBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSheetSurface.surface(dark))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSheetSurface.border(dark), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Detail rows (Web `.detail-item`)

struct AppDetailRow: View {
    let label: String
    let value: String
    var isLast: Bool = false

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppSheetSurface.mutedText(dark))
                .frame(width: 88, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(AppSheetSurface.primaryText(dark))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(
            Group {
                if !isLast {
                    Rectangle()
                        .fill(AppSheetSurface.border(dark))
                        .frame(height: 1)
                }
            },
            alignment: .bottom
        )
    }
}

// MARK: - Multi-line editor

struct AppTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 90
    var monospaced: Bool = false

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: monospaced ? 12 : 13,
                          design: monospaced ? .monospaced : .default))
            .foregroundColor(AppSheetSurface.primaryText(dark))
            .padding(8)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(dark ? Color(hex: "161820") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppSheetSurface.border(dark), lineWidth: 1)
            )
            .colorScheme(dark ? .dark : .light)
    }
}

// MARK: - Info callout (Web blue tip boxes)

struct AppSheetInfoBox: View {
    let text: String
    var lines: [String] = []

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppSheetSurface.accentBlue(dark))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppSheetSurface.accentBlue(dark))
            }
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
                    .font(.system(size: 12))
                    .foregroundColor(AppSheetSurface.mutedText(dark))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSheetSurface.accentBlue(dark).opacity(0.10))
        .cornerRadius(4)
    }
}
