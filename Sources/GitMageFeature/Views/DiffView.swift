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

    @ViewBuilder private func content(_ rows: [Row]) -> some View {
        if rows.contains(where: { $0.kind != .meta }) {
            if embedded {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row($0) }
                    }
                    .padding(.vertical, 4)
                    .textSelection(.enabled)
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    // Plain VStack (not Lazy): a LazyVStack in a bidirectional
                    // ScrollView mis-estimates its height and leaves empty
                    // vertical space below the content.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row($0) }
                    }
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                }
            }
        } else if !embedded {
            EmptyStateView(icon: "doc.text", title: "No textual changes",
                           message: "This change has no line-level diff to show.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No textual changes.")
                .font(AinkradFont.mono(10))
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .padding(8)
        }
    }

    private func header(title: String, rows: [Row]) -> some View {
        let additions = rows.filter { $0.kind == .add }.count
        let deletions = rows.filter { $0.kind == .remove }.count
        return HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(tokens.accentSecondary)
            Text(title)
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.75))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if additions > 0 {
                Text("+\(additions)")
                    .font(AinkradFont.mono(10, weight: .semibold))
                    .foregroundStyle(GMColor.diffAdd(tokens))
            }
            if deletions > 0 {
                Text("−\(deletions)")
                    .font(AinkradFont.mono(10, weight: .semibold))
                    .foregroundStyle(GMColor.diffRemove(tokens))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private func row(_ r: Row) -> some View {
        switch r.kind {
        case .meta:
            EmptyView()   // diff/index/+++/--- headers are noise; hide them
        case .hunk:
            Text(r.text)
                .font(AinkradFont.mono(fontSize - 1, weight: .medium))
                .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(tokens.accentSecondary.opacity(0.08))
        default:
            let color = lineColor(r.kind)
            HStack(spacing: 0) {
                gutter(r.oldNo)
                gutter(r.newNo)
                Text(sign(r.kind))
                    .font(AinkradFont.mono(fontSize))
                    .foregroundStyle(color.opacity(0.9))
                    .frame(width: 16, alignment: .center)
                Text(r.text.isEmpty ? " " : r.text)
                    .font(AinkradFont.mono(fontSize))
                    .foregroundStyle(color)
                Spacer(minLength: 12)
            }
            .padding(.vertical, 0.5)
            .background(lineBackground(r.kind))
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(AinkradFont.mono(max(9, fontSize - 2)))
            .foregroundStyle(tokens.foreground.opacity(0.3))
            .frame(width: 40, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private func lineColor(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens)
        case .remove: return GMColor.diffRemove(tokens)
        default: return tokens.foreground.opacity(0.85)
        }
    }

    private func lineBackground(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens).opacity(0.10)
        case .remove: return GMColor.diffRemove(tokens).opacity(0.10)
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

    /// Turns unified-diff text into gutter-numbered rows, tracking old/new line
    /// counters across hunks.
    private static func parse(_ body: String) -> [Row] {
        var rows: [Row] = []
        var oldLine = 0
        var newLine = 0
        var id = 0
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                let (o, n) = parseHunkHeader(line)
                oldLine = o
                newLine = n
                rows.append(Row(id: id, kind: .hunk, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ")
                        || line.hasPrefix("index ") || line.hasPrefix("new file")
                        || line.hasPrefix("deleted file") || line.hasPrefix("similarity ")
                        || line.hasPrefix("rename ") || line.hasPrefix("old mode") || line.hasPrefix("new mode") {
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

    /// Extracts the starting old/new line numbers from `@@ -a,b +c,d @@`.
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
