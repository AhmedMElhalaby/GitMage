import SwiftUI
import AinkradAppKit

/// Context pane (left rail) for the Issues area: filter + issue list + New
/// Issue entry point, gated on having a GitHub remote and a valid token.
struct IssuesContextPane: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens
    /// Whether the active repo resolved a GitHub `origin` remote. Passed in
    /// from the shell, since the view model does not expose its `repo`.
    let hasGitHubRemote: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch gate {
            case .needsGitHubRemote:
                gateMessage("Issues need a GitHub `origin` remote.")
            case .needsToken:
                gateMessage("Add a GitHub token in Settings.")
            case .invalidToken(let message):
                gateMessage(message)
            case .ready:
                toolbar
                list
            }
        }
        .sheet(isPresented: $model.showNew) {
            NewIssueSheet(model: model, tokens: tokens)
        }
    }

    private enum Gate {
        case needsGitHubRemote
        case needsToken
        case invalidToken(String)
        case ready
    }

    private var gate: Gate {
        guard hasGitHubRemote else { return .needsGitHubRemote }
        switch model.authState {
        case .missingToken: return .needsToken
        case .invalid(let message): return .invalidToken(message)
        case .unknown, .valid: return .ready
        }
    }

    private func gateMessage(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.5))
            Text(text)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.filter) {
                Text("Open").tag(IssueState.open)
                Text("Closed").tag(IssueState.closed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.filter) { _, _ in
                Task { await model.load() }
            }
            Button {
                model.showNew = true
            } label: {
                Label("New Issue", systemImage: "plus")
                    .font(AinkradFont.display(12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.2)))
        }
        .padding(12)
    }

    @ViewBuilder private var list: some View {
        if model.isLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            gateMessage(errorMessage)
        } else if model.issues.isEmpty {
            gateMessage("No issues.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.issues) { issue in
                        IssueRow(
                            issue: issue,
                            tokens: tokens,
                            isSelected: model.selectedNumber == issue.number,
                            onSelect: { Task { await model.select(issue.number) } }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

private struct IssueRow: View {
    let issue: IssueSummary
    let tokens: HostThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.accentPrimary.opacity(0.7))
                VStack(alignment: .leading, spacing: 3) {
                    Text("#\(issue.number)  \(issue.title)")
                        .font(AinkradFont.display(12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(issue.author)
                            .font(AinkradFont.mono(9))
                            .foregroundStyle(tokens.foreground.opacity(0.5))
                        if issue.commentCount > 0 {
                            Label("\(issue.commentCount)", systemImage: "bubble.left")
                                .font(AinkradFont.mono(9))
                                .foregroundStyle(tokens.foreground.opacity(0.45))
                        }
                    }
                    if !issue.labelNames.isEmpty {
                        LabelChipsRow(names: issue.labelNames, tokens: tokens)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                isSelected ? tokens.accentPrimary.opacity(0.13) : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// Small row of neutral label chips, used where only label names (not colors)
/// are available (e.g. issue list rows).
struct LabelChipsRow: View {
    let names: [String]
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(AinkradFont.display(9, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(tokens.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

/// Colored label chip, used where a hex color is available (e.g. issue
/// detail's editable labels control).
struct ColoredLabelChip: View {
    let label: IssueLabel

    var body: some View {
        Text(label.name)
            .font(AinkradFont.display(9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: label.color).opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

extension Color {
    /// Parses a 6-digit hex string (as returned by the GitHub labels API,
    /// no leading `#`) into a `Color`. Falls back to gray if unparseable.
    init(hex: String) {
        var hexValue: UInt64 = 0
        let scanner = Scanner(string: hex)
        guard scanner.scanHexInt64(&hexValue), hex.count == 6 else {
            self = .gray
            return
        }
        let r = Double((hexValue & 0xFF0000) >> 16) / 255
        let g = Double((hexValue & 0x00FF00) >> 8) / 255
        let b = Double(hexValue & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
