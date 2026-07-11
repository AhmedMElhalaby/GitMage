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
    private let tokens: HostThemeTokens
    private let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    init(
        _ title: String,
        kind: GMButtonKind = .secondary,
        systemImage: String? = nil,
        tokens: HostThemeTokens,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
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
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.75 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.14), value: isHovering)
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

    private var fillColor: Color {
        switch kind {
        case .primary:
            return tokens.accentPrimary.opacity(isHovering ? 1.0 : 0.9)
        case .secondary:
            return tokens.surfaceElevated.opacity(isHovering ? 0.7 : 0.5)
        case .subtle:
            return isHovering ? tokens.surfaceElevated.opacity(0.35) : .clear
        case .destructive:
            return tokens.accentTertiary.opacity(isHovering ? 0.22 : 0.12)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return tokens.accentPrimary.opacity(0.4)
        case .secondary:
            return tokens.accentPrimary.opacity(0.2)
        case .subtle:
            return .clear
        case .destructive:
            return tokens.accentTertiary.opacity(0.4)
        }
    }
}
