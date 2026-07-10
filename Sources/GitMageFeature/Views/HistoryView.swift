import SwiftUI
import AinkradAppKit

struct HistoryContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if model.commits.isEmpty {
                    Text("No commits.").font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.5)).padding(12)
                }
                ForEach(model.commits) { commit in
                    Button { model.selectCommit(commit) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.summary).font(AinkradFont.display(12)).lineLimit(1)
                            HStack(spacing: 8) {
                                Text(commit.shortSHA).font(AinkradFont.mono(9)).foregroundStyle(tokens.accentSecondary)
                                Text(commit.author).font(AinkradFont.display(9)).foregroundStyle(tokens.foreground.opacity(0.5))
                                Text(commit.relativeDate).font(AinkradFont.display(9)).foregroundStyle(tokens.foreground.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(model.selectedCommitID == commit.id ? tokens.accentPrimary.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}
