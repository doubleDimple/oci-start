import SwiftUI

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

// MARK: - ProminentButton (replaces .buttonStyle(.borderedProminent) for macOS 11)

struct ProminentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(6)
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
