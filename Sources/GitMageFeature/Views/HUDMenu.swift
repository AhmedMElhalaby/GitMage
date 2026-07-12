import SwiftUI
import AinkradAppKit

/// One row in a `HUDMenu`.
struct HUDMenuItem: Identifiable {
    let id: String
    let title: String
    var isSelected: Bool = false
    var colorHex: String? = nil   // shows a color dot (label chips)
}

/// A HUD replacement for the system `Menu`: the trigger opens a token-styled
/// popover list (font-controlled), instead of an AppKit popup in the system
/// font. Supports single-select (closes on pick) and multi-select (stays open).
struct HUDMenu<Trigger: View>: View {
    let tokens: HostThemeTokens
    let items: [HUDMenuItem]
    var multiSelect: Bool = false
    let onPick: (String) -> Void
    @ViewBuilder let trigger: () -> Trigger

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { trigger() }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ScrollView {
                    VStack(spacing: 1) {
                        if items.isEmpty {
                            Text("None available")
                                .font(AinkradFont.display(11))
                                .foregroundStyle(tokens.foreground.opacity(0.4))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        } else {
                            ForEach(items) { item in
                                HUDMenuRow(item: item, tokens: tokens) {
                                    onPick(item.id)
                                    if !multiSelect { open = false }
                                }
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(minWidth: 190, maxHeight: 320)
                .background(tokens.surface)
            }
    }
}

private struct HUDMenuRow: View {
    let item: HUDMenuItem
    let tokens: HostThemeTokens
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let hex = item.colorHex {
                    Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                }
                Text(item.title)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 16)
                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tokens.accentPrimary)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? tokens.accentPrimary.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
