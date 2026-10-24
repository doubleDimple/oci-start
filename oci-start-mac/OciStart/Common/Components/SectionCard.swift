import SwiftUI

struct SectionCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var appearance: AppearanceController
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { appearance.isDarkEffective || colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title)
                    .font(.system(size: AppTheme.sectionSize, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(dark))
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg(dark))
        .cornerRadius(AppTheme.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.border(dark).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow(dark), radius: AppTheme.cardShadowRadius, y: AppTheme.cardShadowY)
    }
}
