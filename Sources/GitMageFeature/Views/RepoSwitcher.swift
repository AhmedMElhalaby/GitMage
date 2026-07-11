import SwiftUI
import AinkradAppKit

// MARK: - HUD tooltip system

/// Where a tooltip sits relative to its control.
enum TooltipEdge { case bottom, trailing }

/// A pending tooltip: text + the control's bounds anchor + placement edge.
struct TooltipItem: Equatable {
    let text: String
    let anchor: Anchor<CGRect>
    let edge: TooltipEdge
}

/// Bubbles the currently-hovered control's tooltip up to the shell, which
/// renders it above everything (native `.help` proved unreliable in the
/// plugin's hosting view).
struct TooltipKey: PreferenceKey {
    static let defaultValue: TooltipItem? = nil
    static func reduce(value: inout TooltipItem?, nextValue: () -> TooltipItem?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Publishes this view's tooltip while `active` (its hover state).
    func hudTooltip(_ text: String, edge: TooltipEdge, active: Bool) -> some View {
        anchorPreference(key: TooltipKey.self, value: .bounds) { anchor in
            active && !text.isEmpty ? TooltipItem(text: text, anchor: anchor, edge: edge) : nil
        }
    }
}

/// The floating HUD tooltip label the shell positions from the anchor.
struct HUDTooltipLabel: View {
    let text: String
    let tokens: HostThemeTokens

    var body: some View {
        Text(text)
            .font(AinkradFont.display(11, weight: .medium))
            .foregroundStyle(tokens.foreground.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tokens.background.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tokens.accentSecondary.opacity(0.55), tokens.accentPrimary.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tokens.accentPrimary.opacity(0.3), radius: 12, y: 3)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .fixedSize()
            .allowsHitTesting(false)
    }
}

// MARK: - Chips that open the management overlays

/// Top-bar chip that opens the full-surface repo-management overlay.
struct RepoSwitcher: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    var shortcut: String? = nil
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "folder.badge.gearshape",
            label: model.activeRepo?.name ?? "No Repository",
            tooltip: "Repositories",
            shortcut: shortcut,
            tokens: tokens,
            action: onOpen
        )
    }
}

/// Top-bar chip that opens the full-surface branch-management overlay.
struct BranchChip: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    var shortcut: String? = nil
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "arrow.triangle.branch",
            label: model.snapshot?.branchName ?? "—",
            tooltip: "Branches",
            shortcut: shortcut,
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
    var tooltip: String? = nil
    var shortcut: String? = nil
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
        .hudTooltip(shortcutTooltip(tooltip ?? label, shortcut), edge: .bottom, active: hovering)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
    }
}

/// Composes a tooltip: "Fetch  ⌥⌘F" when a shortcut is bound, else just the label.
func shortcutTooltip(_ label: String, _ shortcut: String?) -> String {
    guard let shortcut, !shortcut.isEmpty else { return label }
    return "\(label)  \(shortcut)"
}

// MARK: - Top-bar action button (Fetch / Pull / Push)

/// A gaming-HUD action button with an inline spinner: while `isLoading`, the
/// icon is replaced by a rotating accent arc — no external ProgressView.
struct TopBarActionButton: View {
    let label: String
    let icon: String
    var shortcut: String? = nil
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
        .hudTooltip(shortcutTooltip(label, shortcut), edge: .bottom, active: hovering)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Shared HUD surface finish

enum HUDButtonKind { case chip, secondary, primary, destructive }

private struct HUDButtonSurface: ViewModifier {
    let tokens: HostThemeTokens
    let kind: HUDButtonKind
    let hovering: Bool

    private let radius: CGFloat = 9
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background(fill.clipShape(shape))
            // Glassy top gloss — a soft sheen across the upper half.
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(kind == .primary ? 0.22 : 0.10), .clear],
                    startPoint: .top, endPoint: .center
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            // Gradient rim.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: rimColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
            // Bright "powered edge" along the very top.
            .overlay(alignment: .top) {
                Capsule()
                    .fill(tokens.accentSecondary.opacity(hovering ? 0.75 : 0.35))
                    .frame(height: 1.5)
                    .padding(.horizontal, 7)
                    .blur(radius: 0.5)
            }
            .shadow(color: glowColor, radius: glowRadius, y: hovering ? 3 : 1)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    private var rimColors: [Color] {
        if kind == .destructive {
            return [tokens.accentTertiary.opacity(hovering ? 0.8 : 0.45),
                    tokens.accentTertiary.opacity(hovering ? 0.4 : 0.2)]
        }
        return [tokens.accentSecondary.opacity(hovering ? 0.85 : 0.5),
                tokens.accentPrimary.opacity(hovering ? 0.4 : 0.2)]
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [tokens.accentPrimary.opacity(hovering ? 1 : 0.92),
                         tokens.accentPrimary.opacity(hovering ? 0.9 : 0.72)],
                startPoint: .top, endPoint: .bottom
            )
        case .destructive:
            LinearGradient(
                colors: [tokens.accentTertiary.opacity(hovering ? 0.28 : 0.16),
                         tokens.accentTertiary.opacity(hovering ? 0.18 : 0.10)],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary, .chip:
            LinearGradient(
                colors: [tokens.surfaceElevated.opacity(hovering ? 0.85 : 0.5),
                         tokens.surfaceElevated.opacity(hovering ? 0.55 : 0.28)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var glowColor: Color {
        switch kind {
        case .primary: return tokens.accentPrimary.opacity(hovering ? 0.55 : 0.35)
        case .destructive: return tokens.accentTertiary.opacity(hovering ? 0.4 : 0.1)
        case .secondary, .chip: return tokens.accentPrimary.opacity(hovering ? 0.32 : 0.06)
        }
    }

    private var glowRadius: CGFloat {
        switch kind {
        case .primary: return hovering ? 14 : 9
        case .destructive: return hovering ? 12 : 4
        case .secondary, .chip: return hovering ? 11 : 3
        }
    }
}

extension View {
    func hudButtonSurface(tokens: HostThemeTokens, kind: HUDButtonKind, hovering: Bool) -> some View {
        modifier(HUDButtonSurface(tokens: tokens, kind: kind, hovering: hovering))
    }
}

// MARK: - Nav rail item

/// A single icon in the left nav rail, in the gaming-HUD language: a glowing
/// leading "spine" indicator and a bordered accent tile slide to the active
/// area via a shared matched-geometry namespace; hover lifts inactive icons.
struct NavRailItem: View {
    let area: NavArea
    let isActive: Bool
    let tokens: HostThemeTokens
    let namespace: Namespace.ID
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Leading spine — the moving active indicator.
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tokens.accentSecondary)
                            .frame(width: 3, height: 20)
                            .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 5)
                            .matchedGeometryEffect(id: "navSpine", in: namespace)
                    }
                }
                .frame(width: 5)

                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tokens.accentPrimary.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [tokens.accentSecondary.opacity(0.6),
                                                     tokens.accentPrimary.opacity(0.25)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: tokens.accentPrimary.opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "navTile", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    }

                    Image(systemName: area.icon)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? tokens.accentPrimary
                                         : tokens.foreground.opacity(hovering ? 0.9 : 0.6))
                        .shadow(color: isActive ? tokens.accentPrimary.opacity(0.7) : .clear, radius: 5)
                }
                .frame(width: 40, height: 36)
            }
            .frame(width: 52, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudTooltip(shortcutTooltip(area.title, shortcut), edge: .trailing, active: hovering)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hovering = h } }
    }
}

// MARK: - Keyboard shortcut dispatch

/// An invisible layer of zero-size buttons, one per bound command, each
/// carrying its `.keyboardShortcut`. Placed in the shell background so the
/// bindings fire window-wide without depending on which control is on screen.
struct ShortcutLayer: View {
    let shortcuts: [String: KeyChord]
    let hasActiveRepo: Bool
    let perform: (GitMageCommand) -> Void

    var body: some View {
        ZStack {
            ForEach(GitMageCommand.allCases) { command in
                if let chord = shortcuts[command.rawValue],
                   chord.hasModifier,
                   let equivalent = chord.keyEquivalent {
                    Button(action: { perform(command) }) { Color.clear.frame(width: 0, height: 0) }
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .keyboardShortcut(equivalent, modifiers: chord.eventModifiers)
                        .disabled(command.requiresRepo && !hasActiveRepo)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
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
