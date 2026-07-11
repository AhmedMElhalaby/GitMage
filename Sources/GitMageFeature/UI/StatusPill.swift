import SwiftUI
import AinkradAppKit

/// A small capsule badge for status text (PR/issue state, op result). Uses
/// the same tinted-fill / full-color-text pattern across all status kinds so
/// pills read consistently regardless of theme.
struct StatusPill: View {
    let text: String
    let kind: GMStatusKind
    let tokens: HostThemeTokens

    var body: some View {
        let color = GMColor.status(kind, tokens)
        Text(text)
            .font(AinkradFont.display(10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }
}
