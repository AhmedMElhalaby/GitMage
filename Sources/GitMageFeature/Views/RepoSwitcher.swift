import SwiftUI
import AinkradAppKit

// MARK: - Chips that open the management overlays

/// Top-bar chip that opens the full-surface repo-management overlay.
struct RepoSwitcher: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "folder.badge.gearshape",
            label: model.activeRepo?.name ?? "No Repository",
            tokens: tokens,
            action: onOpen
        )
    }
}

/// Top-bar chip that opens the full-surface branch-management overlay.
struct BranchChip: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "arrow.triangle.branch",
            label: model.snapshot?.branchName ?? "—",
            tokens: tokens,
            action: onOpen
        )
    }
}

// MARK: - Shared HUD chip

/// A gaming-HUD trigger: translucent fill, gradient accent border, accent
/// glow on hover, glowing leading icon and a chevron affordance.
struct TopBarChip: View {
    let icon: String
    let label: String
    let tokens: HostThemeTokens
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.accentSecondary)
                    .shadow(color: tokens.accentSecondary.opacity(hovering ? 0.8 : 0.4), radius: hovering ? 5 : 2)
                Text(label)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(hovering ? 0.7 : 0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hudButtonSurface(tokens: tokens, kind: .chip, hovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Top-bar action button (Fetch / Pull / Push)

/// A gaming-HUD action button with an inline spinner: while `isLoading`, the
/// icon is replaced by a rotating accent arc — no external ProgressView.
struct TopBarActionButton: View {
    let label: String
    let icon: String
    var isPrimary: Bool = false
    let isLoading: Bool
    let tokens: HostThemeTokens
    let action: () -> Void
    @State private var hovering = false

    private var iconTint: Color {
        isPrimary ? .white.opacity(0.95) : tokens.accentSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    if isLoading {
                        GMSpinner(tint: iconTint, size: 13)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                }
                .frame(width: 14, height: 14)
                Text(label)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(isPrimary ? .white.opacity(0.95) : tokens.foreground.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hudButtonSurface(tokens: tokens, kind: isPrimary ? .primary : .secondary, hovering: hovering)
            .contentShape(Rectangle())
            .opacity(isLoading ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Shared HUD surface finish

enum HUDButtonKind { case chip, secondary, primary }

private struct HUDButtonSurface: ViewModifier {
    let tokens: HostThemeTokens
    let kind: HUDButtonKind
    let hovering: Bool

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tokens.accentSecondary.opacity(hovering ? 0.7 : 0.4),
                                     tokens.accentPrimary.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                // Thin top highlight — the "powered edge" of the HUD button.
                RoundedRectangle(cornerRadius: 1)
                    .fill(tokens.accentSecondary.opacity(hovering ? 0.5 : 0.22))
                    .frame(height: 1)
                    .padding(.horizontal, 6)
            }
            .shadow(color: glowColor, radius: glowRadius, y: 1)
    }

    @ViewBuilder private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch kind {
        case .primary:
            shape.fill(
                LinearGradient(
                    colors: [tokens.accentPrimary.opacity(hovering ? 1 : 0.9),
                             tokens.accentPrimary.opacity(hovering ? 0.85 : 0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        case .secondary, .chip:
            shape.fill(tokens.surfaceElevated.opacity(hovering ? 0.7 : 0.4))
        }
    }

    private var glowColor: Color {
        switch kind {
        case .primary: return tokens.accentPrimary.opacity(hovering ? 0.5 : 0.32)
        case .secondary, .chip: return tokens.accentPrimary.opacity(hovering ? 0.28 : 0)
        }
    }

    private var glowRadius: CGFloat {
        switch kind {
        case .primary: return hovering ? 12 : 8
        case .secondary, .chip: return hovering ? 9 : 0
        }
    }
}

private extension View {
    func hudButtonSurface(tokens: HostThemeTokens, kind: HUDButtonKind, hovering: Bool) -> some View {
        modifier(HUDButtonSurface(tokens: tokens, kind: kind, hovering: hovering))
    }
}

// MARK: - Inline spinner

/// A rotating accent arc — the in-button loading indicator, on-brand rather
/// than a stock ProgressView.
struct GMSpinner: View {
    let tint: Color
    var size: CGFloat = 13
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [tint.opacity(0), tint]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
    }
}
