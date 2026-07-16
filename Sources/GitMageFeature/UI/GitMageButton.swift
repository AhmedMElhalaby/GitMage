import SwiftUI
import AinkradAppKit

/// Visual weight of a `GMButton`.
enum GMButtonKind {
    case primary
    case secondary
    case subtle
    case destructive
}

/// The shared button primitive for Git Mage surfaces — token-driven fill,
/// hover/pressed feedback, and a consistent label style. Replaces ad-hoc
/// `Button` styling across the plugin.
struct GMButton: View {
    private let title: String
    private let kind: GMButtonKind
    private let systemImage: String?
    private let tooltip: String?
    private let tokens: HostThemeTokens
    private let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    init(
        _ title: String,
        kind: GMButtonKind = .secondary,
        systemImage: String? = nil,
        tooltip: String? = nil,
        tokens: HostThemeTokens,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
        self.tooltip = tooltip
        self.tokens = tokens
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(AinkradFont.display(12, weight: .medium))
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hudButtonSurface(tokens: tokens, kind: hudKind, hovering: isHovering)
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.8 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .hudTooltip(tooltip ?? "", edge: .bottom, active: isHovering)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }

    /// Maps the semantic kind onto the shared HUD button surface used across
    /// the top bar, so every GMButton reads as one family.
    private var hudKind: HUDButtonKind {
        switch kind {
        case .primary: return .primary
        case .secondary: return .secondary
        case .subtle: return .chip
        case .destructive: return .destructive
        }
    }

    private var labelColor: Color {
        switch kind {
        case .primary:
            return .white.opacity(0.95)
        case .secondary:
            return tokens.foreground.opacity(isHovering ? 0.95 : 0.85)
        case .subtle:
            return tokens.foreground.opacity(isHovering ? 0.85 : 0.65)
        case .destructive:
            return tokens.accentTertiary
        }
    }
}
