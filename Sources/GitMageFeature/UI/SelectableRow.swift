import SwiftUI
import AinkradAppKit

/// A tappable list row with selected/hover background states, used for
/// worktree/PR/issue lists across Git Mage. Wraps arbitrary row content.
struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let tokens: HostThemeTokens
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ChamferShape(cut: AinkradRadius.md)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                hovering = isHovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return tokens.accentPrimary.opacity(0.13)
        }
        if hovering {
            return tokens.surfaceElevated.opacity(0.5)
        }
        return .clear
    }
}
