import SwiftUI
import AppKit

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8)  & 0xFF) / 255
            b = Double(int         & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - App Theme (aligned with web dark/light tokens)
// Support floor: macOS Big Sur 11.7.11+

enum AppTheme {
    // Backgrounds
    static func pageBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1a1d21") : Color(hex: "f0f4f8")
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "22262b") : Color.white
    }
    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1e2124") : Color(hex: "F3F4F6")
    }
    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "292d32") : Color(hex: "F3F4F6")
    }

    // Text
    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "cdd9e5") : Color(hex: "111827")
    }
    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "768390") : Color(hex: "6B7280")
    }

    // Borders / lines
    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "31363d") : Color(hex: "D1D5DB")
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "31363d") : Color(hex: "dde3ec")
    }

    // Accents
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "2563eb")
    }
    static func accentButton(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "4d9eff") : Color(hex: "111827")
    }
    static let success = Color(hex: "3fb950")
    static let warning = Color(hex: "f78166")
    static let danger  = Color(hex: "ff6b6b")
    static let cyan    = Color(hex: "39c5cf")

    // Login-specific
    static func loginOuterBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1a1d21") : Color(hex: "ECEEF2")
    }
}

// MARK: - ProminentButton (replaces .buttonStyle(.borderedProminent) for macOS 11)

struct ProminentButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(AppTheme.accentButton(scheme).opacity(configuration.isPressed ? 0.8 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

struct CapsulePrimaryButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(AppTheme.accentButton(scheme).opacity(disabled ? 0.45 : (configuration.isPressed ? 0.85 : 1)))
            )
    }
}

// MARK: - Shake modifier (empty field validation)

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0)
        )
    }
}

struct ShakeModifier: ViewModifier {
    var trigger: Int
    @State private var shake: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: shake))
            .onChange(of: trigger) { _ in
                shake = 0
                withAnimation(.linear(duration: 0.4)) { shake = 1 }
            }
    }
}

extension View {
    func shake(trigger: Int) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

// MARK: - Empty / Loading states

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(AppTheme.muted(scheme))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.text(scheme))
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.muted(scheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct PageLoadingView: View {
    var message: String = "加载中…"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.9)
            Text(message)
                .font(.callout)
                .foregroundColor(AppTheme.muted(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toast (shared)

struct AppToastView: View {
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(AppTheme.accentButton(scheme))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.15), radius: 10, y: 4)
    }
}

// MARK: - SF Symbol fallback (prefer symbols available on Big Sur)

enum AppIcon {
    /// Prefer first symbol that exists conceptually on 11.x; callers use systemName directly.
    static func name(_ preferred: String, fallback: String) -> String {
        // Big Sur has a large SF Symbols 2 set; when unsure use fallback.
        if #available(macOS 12.0, *) {
            return preferred
        }
        return fallback
    }
}

// MARK: - URLSession compat wrappers (replaces async/await variants available macOS 12+)

extension URLSession {
    func compatData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            dataTask(with: request) { data, response, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (data ?? Data(), response ?? URLResponse()))
            }.resume()
        }
    }

    func compatData(from url: URL) async throws -> (Data, URLResponse) {
        try await compatData(for: URLRequest(url: url))
    }
}
