import SwiftUI
import AinkradAppKit

struct DiffView: View {
    let diff: GitDiffSnapshot?
    let tokens: HostThemeTokens
    let fontSize: Double
    /// Embedded mode (e.g. inside an expanded file row): no own vertical scroll
    /// and no header — the diff flows in the parent's scroll.
    var embedded: Bool = false
    var showHeader: Bool = true

    private let numberWidth: CGFloat = 34
    private let signWidth: CGFloat = 16
    private var gutterWidth: CGFloat { numberWidth * 2 + 8 }

    private enum LineKind { case hunk, add, remove, context, meta }
    private struct Row: Identifiable {
        let id: Int
        let kind: LineKind
        let oldNo: Int?
        let newNo: Int?
        let text: String
    }

    var body: some View {
        if let diff {
            let rows = Self.parse(diff.body)
            VStack(alignment: .leading, spacing: 0) {
                if showHeader {
                    header(title: diff.title, rows: rows)
                    GlowRule(tokens: tokens)
                }
                content(rows)
            }
            .frame(maxWidth: .infinity, maxHeight: embedded ? nil : .infinity, alignment: .topLeading)
        } else if !embedded {
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "No file selected",
                           message: "Select a file, commit, or stash to inspect its diff.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(title: String, rows: [Row]) -> some View {
        let additions = rows.filter { $0.kind == .add }.count
        let deletions = rows.filter { $0.kind == .remove }.count
        return HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(tokens.accentSecondary)
            Text(title)
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.75))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if additions > 0 {
                Text("+\(additions)").font(AinkradFont.mono(10, weight: .semibold)).foregroundStyle(GMColor.diffAdd(tokens))
            }
            if deletions > 0 {
                Text("−\(deletions)").font(AinkradFont.mono(10, weight: .semibold)).foregroundStyle(GMColor.diffRemove(tokens))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private func content(_ rows: [Row]) -> some View {
        if rows.contains(where: { $0.kind != .meta }) {
            // Uniform code width so add/remove tints line up like GitHub, and
            // long lines scroll horizontally without wrapping.
            let maxLen = rows.filter { $0.kind != .meta }
                .map { displayText($0).count }.max() ?? 0
            let codeWidth = max(CGFloat(maxLen) * CGFloat(fontSize) * 0.62 + 10, 80)
            let stack = VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row($0, codeWidth: codeWidth) }
            }
            .padding(.vertical, 4)
            .textSelection(.enabled)

            if embedded {
                ScrollView(.horizontal, showsIndicators: false) { stack }
            } else {
                ScrollView([.vertical, .horizontal]) { stack }
            }
        } else if !embedded {
            EmptyStateView(icon: "doc.text", title: "No textual changes",
                           message: "This change has no line-level diff to show.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No textual changes.")
                .font(AinkradFont.mono(10)).foregroundStyle(tokens.foreground.opacity(0.4)).padding(8)
        }
    }

    @ViewBuilder private func row(_ r: Row, codeWidth: CGFloat) -> some View {
        switch r.kind {
        case .meta:
            EmptyView()
        case .hunk:
            HStack(spacing: 0) {
                Color.clear.frame(width: gutterWidth + signWidth)
                Text(r.text)
                    .font(AinkradFont.mono(fontSize - 1, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: codeWidth, alignment: .leading)
                    .padding(.leading, 4)
            }
            .background(tokens.accentSecondary.opacity(0.08))
        default:
            HStack(spacing: 0) {
                gutterCell(r.oldNo, r.newNo)
                Text(sign(r.kind))
                    .font(AinkradFont.mono(fontSize))
                    .foregroundStyle(signColor(r.kind))
                    .frame(width: signWidth, alignment: .center)
                Text(SyntaxHighlighter.highlight(displayText(r), tokens: tokens))
                    .font(AinkradFont.mono(fontSize))
                    .lineLimit(1)
                    .frame(width: codeWidth, alignment: .leading)
                    .padding(.trailing, 8)
            }
            .background(lineBackground(r.kind))
        }
    }

    private func gutterCell(_ old: Int?, _ new: Int?) -> some View {
        HStack(spacing: 0) {
            Text(old.map(String.init) ?? "")
                .frame(width: numberWidth, alignment: .trailing)
            Text(new.map(String.init) ?? "")
                .frame(width: numberWidth, alignment: .trailing)
        }
        .font(AinkradFont.mono(max(9, fontSize - 2)))
        .foregroundStyle(tokens.foreground.opacity(0.3))
        .padding(.trailing, 8)
        .background(tokens.foreground.opacity(0.03))
    }

    /// Tab-expanded text for a row (tabs → 4 spaces) so columns align.
    private func displayText(_ r: Row) -> String {
        r.text.replacingOccurrences(of: "\t", with: "    ")
    }

    private func signColor(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens)
        case .remove: return GMColor.diffRemove(tokens)
        default: return tokens.foreground.opacity(0.3)
        }
    }

    private func lineBackground(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens).opacity(0.12)
        case .remove: return GMColor.diffRemove(tokens).opacity(0.12)
        default: return .clear
        }
    }

    private func sign(_ kind: LineKind) -> String {
        switch kind {
        case .add: return "+"
        case .remove: return "−"
        default: return " "
        }
    }

    // MARK: - Parsing

    private static func parse(_ body: String) -> [Row] {
        var rows: [Row] = []
        var oldLine = 0
        var newLine = 0
        var id = 0
        // Track whether we're inside a hunk. File headers (---/+++/index/…) only
        // appear BETWEEN `diff --git` and the first `@@`; once in a hunk, a line
        // starting with `-`/`+` is content — even "--- foo" (SQL/Markdown) or
        // "+++x". Prefix alone can't disambiguate, so gate headers on !inHunk.
        var inHunk = false
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("diff --git") {
                inHunk = false
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("@@") {
                let (o, n) = parseHunkHeader(line)
                oldLine = o
                newLine = n
                inHunk = true
                rows.append(Row(id: id, kind: .hunk, oldNo: nil, newNo: nil, text: line))
            } else if !inHunk {
                // Everything before a file's first hunk is header/meta.
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — not a content line.
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("+") {
                rows.append(Row(id: id, kind: .add, oldNo: nil, newNo: newLine, text: String(line.dropFirst())))
                newLine += 1
            } else if line.hasPrefix("-") {
                rows.append(Row(id: id, kind: .remove, oldNo: oldLine, newNo: nil, text: String(line.dropFirst())))
                oldLine += 1
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                rows.append(Row(id: id, kind: .context, oldNo: oldLine, newNo: newLine, text: text))
                oldLine += 1
                newLine += 1
            }
            id += 1
        }
        return rows
    }

    private static func parseHunkHeader(_ line: String) -> (Int, Int) {
        var oldStart = 0
        var newStart = 0
        for token in line.split(separator: " ") {
            if token.hasPrefix("-") {
                oldStart = Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
            } else if token.hasPrefix("+") {
                newStart = Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
            }
        }
        return (oldStart, newStart)
    }
}
