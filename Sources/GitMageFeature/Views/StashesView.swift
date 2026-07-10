import SwiftUI
import AinkradAppKit

struct StashesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STASHES").font(AinkradFont.display(10, weight: .semibold)).kerning(2).foregroundStyle(tokens.foreground.opacity(0.5))
                Spacer()
                Button { model.stashChanges() } label: { Label("Stash", systemImage: "tray.and.arrow.down").font(AinkradFont.display(11)) }
                    .buttonStyle(.plain).foregroundStyle(tokens.accentPrimary)
            }
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if model.stashes.isEmpty {
                        Text("No stashes.").font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.5))
                    }
                    ForEach(model.stashes) { stash in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stash.message).font(AinkradFont.display(12)).lineLimit(2)
                            HStack(spacing: 10) {
                                Text(stash.id).font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.5))
                                Spacer()
                                Button("Apply") { model.applyStash(stash) }.buttonStyle(.plain).font(AinkradFont.display(10)).foregroundStyle(tokens.accentPrimary)
                                Button("Pop") { model.popLatestStash() }.buttonStyle(.plain).font(AinkradFont.display(10)).foregroundStyle(tokens.accentPrimary)
                                Button("Drop") { model.dropStash(stash) }.buttonStyle(.plain).font(AinkradFont.display(10)).foregroundStyle(tokens.foreground.opacity(0.6))
                            }
                        }
                        .padding(10)
                        .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}
