import SwiftUI
import AppKit

enum AppButtonStyleKind {
    case primary, secondary, danger, plain
}

private enum TableActionColors {
    static func fill(_ dark: Bool, hovered: Bool, pressed: Bool, enabled: Bool) -> Color {
        if enabled && pressed { return AppTheme.mix(AppTheme.sidebarActive, fraction: 0.20, with: AppTheme.cardBg(dark)) }
        if enabled && hovered { return AppTheme.statusBg(AppTheme.sidebarActive, dark) }
        return AppTheme.hover(dark).opacity(enabled ? 0.65 : 0.35)
    }

    static func border(_ dark: Bool, hovered: Bool, pressed: Bool, enabled: Bool) -> Color {
        enabled && (hovered || pressed) ? AppTheme.sidebarActive.opacity(0.55) : AppTheme.border(dark).opacity(0.65)
    }

    static func foreground(_ dark: Bool, hovered: Bool, enabled: Bool) -> Color {
        if !enabled { return AppTheme.textMuted(dark) }
        return hovered ? AppTheme.sidebarActive : AppTheme.textSecondary(dark)
    }
}

/// Native row menu anchor. Retains NSButton's target/action, keyboard handling,
/// accessibility role and window coordinates used by the existing presenters.
final class TableActionButton: NSButton {
    private var dark = false
    private var hovered = false
    private var pressed = false
    private var hoverArea: NSTrackingArea?

    init(dark: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        title = ""
        bezelStyle = .shadowlessSquare
        isBordered = false
        setButtonType(.momentaryPushIn)
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        focusRingType = .exterior
        setAccessibilityIdentifier("table.row.more")
        updateAppearance(dark: dark)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 30) }
    override var acceptsFirstResponder: Bool { isEnabled }

    func updateAppearance(dark: Bool) {
        self.dark = dark
        let label = LanguageManager.shared.text("更多操作", "More actions")
        toolTip = label
        setAccessibilityLabel(label)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let area = hoverArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
        defer { pressed = false; needsDisplay = true }
        super.mouseDown(with: event)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let down = pressed || cell?.isHighlighted == true
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor(TableActionColors.fill(dark, hovered: hovered, pressed: down, enabled: isEnabled)).setFill()
        shape.fill()
        NSColor(TableActionColors.border(dark, hovered: hovered, pressed: down, enabled: isEnabled)).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let tint = NSColor(TableActionColors.foreground(dark, hovered: hovered || down, enabled: isEnabled))
        if contentTintColor != tint { contentTintColor = tint }
        super.draw(dirtyRect)
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 7, yRadius: 7).fill()
    }
}

/// The same compact icon for SwiftUI's native Menu, preserving its menu tracking
/// and keyboard focus rather than adding a competing click gesture to the label.
struct TableActionMenuLabel: View {
    let title: String
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 30, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel(title)
            .accessibilityIdentifier("table.row.more")
    }
}

/// Big Sur's Menu ignores ButtonStyle. Draw the shared chrome around the
/// native menu control itself, retaining AppKit menu tracking and keyboard use.
struct TableActionMenuChrome: ViewModifier {
    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func body(content: Content) -> some View {
        let dark = appearance.isDarkEffective
        return content
            .frame(width: 30, height: 30)
            .foregroundColor(TableActionColors.foreground(dark, hovered: hovered, enabled: enabled))
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(TableActionColors.fill(dark, hovered: hovered, pressed: false, enabled: enabled)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(TableActionColors.border(dark, hovered: hovered, pressed: false, enabled: enabled), lineWidth: 1)
                .allowsHitTesting(false))
            .onHover { hovered = $0 }
    }
}

struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: AppButtonStyleKind = .primary
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var parentEnabled
    @State private var hovering = false
    private var dark: Bool { appearance.isDarkEffective }
    private var available: Bool { enabled && parentEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        .colorScheme(kind == .primary || kind == .danger ? .dark : (dark ? .dark : .light))
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: AppTheme.bodySize, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(AppTheme.controlRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                    .stroke(borderColor, lineWidth: kind == .secondary ? 1 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled || isLoading)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var background: Color {
        switch kind {
        case .primary:
            if !available { return AppTheme.mix(AppTheme.sidebarActive, fraction: 0.5, with: AppTheme.cardBg(dark)) }
            return hovering ? AppTheme.brandHover : AppTheme.sidebarActive
        case .danger:
            return AppTheme.mix(AppTheme.danger, fraction: available ? (hovering ? 0.7 : 1) : 0.5, with: AppTheme.cardBg(dark))
        case .secondary:
            if !available { return AppTheme.hover(dark) }
            return hovering ? AppTheme.statusBg(AppTheme.success, dark) : AppTheme.cardBg(dark)
        case .plain: return available && hovering ? AppTheme.hover(dark) : .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return !available ? AppTheme.textMuted(dark) : (hovering ? AppTheme.sidebarActive : AppTheme.textPrimary(dark))
        case .plain: return available ? AppTheme.sidebarActive : AppTheme.textMuted(dark)
        }
    }

    private var borderColor: Color {
        kind == .secondary ? (available && hovering ? AppTheme.sidebarActive : AppTheme.border(dark)) : .clear
    }
}
