import SwiftUI
import AinkradAppKit

/// The shared context-pane header: a kerned title, a count pill, and optional
/// trailing actions — the same language as the Changes group headers.
struct PaneHeader<Trailing: View>: View {
    let title: String
    let count: Int
    /// Overrides the count pill text (e.g. "50 / 342"); defaults to `count`.
    let countText: String?
    let tokens: HostThemeTokens
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, count: Int, countText: String? = nil, tokens: HostThemeTokens,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self.countText = countText
        self.tokens = tokens
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AinkradFont.display(10, weight: .semibold)).kerning(2)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            Text(countText ?? "\(count)")
                .font(AinkradFont.mono(9, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(0.6)))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

/// A two-or-more option HUD filter, rendered as accent pills inside a
/// translucent track. Used for Open/Closed filters.
struct HUDFilter<Tag: Hashable>: View {
    let options: [(title: String, tag: Tag)]
    @Binding var selection: Tag
    let tokens: HostThemeTokens
    var onChange: () -> Void = {}

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.tag) { option in
                let isOn = option.tag == selection
                Button {
                    if selection != option.tag { selection = option.tag; onChange() }
                } label: {
                    Text(option.title)
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(isOn ? tokens.accentPrimary : tokens.foreground.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isOn ? tokens.accentPrimary.opacity(0.16) : .clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(isOn ? tokens.accentPrimary.opacity(0.4) : .clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(tokens.surfaceElevated.opacity(0.4)))
    }
}

/// Horizontal accent glow rule — the soft separator used across surfaces.
struct GlowRule: View {
    let tokens: HostThemeTokens
    var body: some View {
        LinearGradient(
            colors: [.clear, tokens.accentPrimary.opacity(0.4), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// A HUD-styled trigger label for a `Menu` (the dropdown popup itself stays
/// system-rendered): value/placeholder text + a chevron on a translucent chip.
struct HUDMenuLabel: View {
    let text: String
    var isPlaceholder: Bool = false
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(isPlaceholder ? 0.5 : 0.9))
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.accentPrimary.opacity(0.18)))
    }
}

/// A horizontally-scrolling row of toggleable label chips (color dot + name).
struct LabelFilterBar: View {
    let labels: [IssueLabel]
    let selected: Set<String>
    let tokens: HostThemeTokens
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels) { label in
                    let isOn = selected.contains(label.name)
                    Button { onToggle(label.name) } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: label.color)).frame(width: 7, height: 7)
                            Text(label.name)
                                .font(AinkradFont.display(10, weight: .medium))
                                .foregroundStyle(isOn ? tokens.accentPrimary : tokens.foreground.opacity(0.75))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? tokens.accentPrimary.opacity(0.16) : tokens.surfaceElevated.opacity(0.4)))
                        .overlay(Capsule().strokeBorder(isOn ? tokens.accentPrimary.opacity(0.5) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
