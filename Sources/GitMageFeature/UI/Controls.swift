import SwiftUI
import AinkradAppKit

/// A section header with a glowing accent tick, shared across Settings sections.
/// Retyped from the host's `SettingsSectionHeader` to take `HostThemeTokens`.
struct SettingsSectionHeader: View {
    let title: String
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentSecondary)
                .frame(width: 3, height: 12)
                .shadow(color: tokens.accentSecondary.opacity(0.8), radius: 4)
            Text(title)
                .font(AinkradFont.fixedDisplay(11, weight: .semibold))
                .kerning(3)
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
    }
}

/// A neon capsule toggle in place of the stock macOS switch: the track
/// lights with the accent when on, the knob carries a soft glow. Shared
/// across the Settings sections. Retyped to take `HostThemeTokens`.
struct NeonToggle: View {
    @Binding var isOn: Bool
    let tokens: HostThemeTokens

    var body: some View {
        // Kit toggle: chamfered track + luminous thumb; on-tint is the kit's
        // accentPrimary, matching the previous NeonToggle on-state. `tokens` is
        // retained on the API so call sites stay untouched.
        AinkradToggle(isOn: $isOn)
    }
}

/// Corner targeting brackets drawn around a selected element (the HUD accent
/// framing). Copied from the host launcher chrome.
struct TargetingBrackets: Shape {
    var length: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
