import SwiftUI
import AinkradAppKit

struct StashesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    @State private var selectedStashID: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "STASHES", count: model.stashes.count, tokens: tokens) {
                HStack(spacing: 6) {
                    RowIconButton(symbol: "tray.and.arrow.down", help: "Stash changes", tokens: tokens) {
                        model.stashChanges()
                    }
                    RowIconButton(symbol: "tray.and.arrow.up", help: "Pop latest stash", tokens: tokens) {
                        model.popLatestStash()
                    }
                    .opacity(model.stashes.isEmpty || model.isLoading ? 0.4 : 1)
                    .allowsHitTesting(!model.stashes.isEmpty && !model.isLoading)
                }
            }

            if model.stashes.isEmpty {
                EmptyStateView(
                    icon: "tray.2",
                    title: "No stashes",
                    message: "Stash your working changes to set them aside.",
                    tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.stashes) { stash in
                            StashRow(
                                stash: stash,
                                isSelected: selectedStashID == stash.id,
                                tokens: tokens,
                                onSelect: { selectedStashID = stash.id; model.selectStash(stash) },
                                onApply: { model.applyStash(stash) },
                                onDrop: { model.dropStash(stash) }
                            )
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
    }
}

private struct StashRow: View {
    let stash: GitStashEntry
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onApply: () -> Void
    let onDrop: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(stash.message)
                    .font(AinkradFont.display(12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(2)
                Text(stash.id)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
            Spacer(minLength: 4)

            HStack(spacing: 4) {
                RowIconButton(symbol: "arrow.down.circle", help: "Apply", tokens: tokens, action: onApply)
                RowIconButton(symbol: "trash", help: "Drop", tokens: tokens, action: onDrop)
            }
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.13)
                      : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(tokens.accentPrimary)
                    .frame(width: 3, height: 20)
                    .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}
