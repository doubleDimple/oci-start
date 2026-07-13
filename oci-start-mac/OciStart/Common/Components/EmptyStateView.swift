import SwiftUI

struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String = "暂无数据"
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(AppTheme.sidebarText(dark).opacity(0.55))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(dark ? Color.white.opacity(0.85) : Color.primary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.sidebarText(dark))
                    .multilineTextAlignment(.center)
            }
            if let actionTitle = actionTitle, let action = action {
                AppButton(title: actionTitle, kind: .primary, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
