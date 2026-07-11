import SwiftUI
import AinkradAppKit

struct DiffView: View {
    let diff: GitDiffSnapshot?
    let tokens: HostThemeTokens
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let diff {
                Text(diff.title)
                    .font(AinkradFont.mono(11, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                            diffLine(String(raw))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .textSelection(.enabled)
                }
            } else {
                VStack { Text("Select a file to inspect its diff.").font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.5)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func colorAndBackground(for line: String) -> (Color, Color) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return (GMColor.diffAdd(tokens), GMColor.diffAdd(tokens).opacity(0.08)) }
        else if line.hasPrefix("-") && !line.hasPrefix("---") { return (GMColor.diffRemove(tokens), GMColor.diffRemove(tokens).opacity(0.08)) }
        else if line.hasPrefix("@@") { return (tokens.accentSecondary, .clear) }
        else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") { return (tokens.foreground.opacity(0.4), .clear) }
        else { return (tokens.foreground.opacity(0.85), .clear) }
    }

    @ViewBuilder private func diffLine(_ line: String) -> some View {
        let (color, bg) = colorAndBackground(for: line)

        Text(line.isEmpty ? " " : line)
            .font(AinkradFont.mono(fontSize))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .background(bg)
    }
}
