import SwiftUI
import AinkradAppKit

/// Context pane (left rail) for the Pull Requests area: filter + PR list,
/// gated on having a GitHub remote and a valid token.
struct PullRequestsContextPane: View {
    @ObservedObject var model: PullRequestsViewModel
    let tokens: HostThemeTokens
    /// Whether the active repo resolved a GitHub `origin` remote. Passed in
    /// from the shell, since the view model does not expose its `repo`.
    let hasGitHubRemote: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch gate {
            case .needsGitHubRemote:
                gateMessage("Pull Requests need a GitHub `origin` remote.")
            case .needsToken:
                gateMessage("Add a GitHub token in Settings.")
            case .invalidToken(let message):
                gateMessage(message)
            case .ready:
                filterBar
                list
            }
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
            Image(systemName: "arrow.triangle.pull")
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

    private var filterBar: some View {
        Picker("", selection: $model.filter) {
            Text("Open").tag(PRState.open)
            Text("Closed").tag(PRState.closed)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(12)
        .onChange(of: model.filter) { _, _ in
            Task { await model.load() }
        }
    }

    @ViewBuilder private var list: some View {
        if model.isLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            gateMessage(errorMessage)
        } else if model.pullRequests.isEmpty {
            gateMessage("No pull requests.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.pullRequests) { pr in
                        PullRequestRow(
                            pr: pr,
                            tokens: tokens,
                            isSelected: model.selectedPRNumber == pr.number,
                            onSelect: { Task { await model.select(pr.number) } }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

private struct PullRequestRow: View {
    let pr: PullRequestSummary
    let tokens: HostThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.accentPrimary.opacity(0.7))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)  \(pr.title)")
                            .font(AinkradFont.display(12, weight: .medium))
                            .lineLimit(1)
                        if pr.isDraft {
                            Text("Draft")
                                .font(AinkradFont.display(9, weight: .semibold))
                                .foregroundStyle(tokens.foreground.opacity(0.55))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(tokens.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text(pr.author)
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
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
