import SwiftUI

extension View {
    /// Page-local overlay. Prefer empty `message` for native spinner-only style.
    func appLoading(_ isLoading: Bool, message: String = "") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }

    /// Embed status overlay (loading HUD + error toast). Prefer shell-level host.
    func withToastHost() -> some View {
        ZStack {
            self
            StatusOverlayHost()
        }
    }
}
