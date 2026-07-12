import SwiftUI
import AinkradAppKit

/// Detail pane for the Pull Requests area: header + Conversation/Files switch.
struct PullRequestDetailView: View {
    @ObservedObject var model: PullRequestsViewModel
    let tokens: HostThemeTokens
    let fontSize: Double

    @State private var tab: Tab = .conversation
    @State private var composerText = ""

    private enum Tab: String, CaseIterable {
        case conversation = "Conversation"
        case commits = "Commits"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                header(detail)
                tabBar

                switch tab {
                case .conversation:
                    conversation(detail)
                case .commits:
                    commitsTab
                case .files:
                    filesTab
                }
            } else {
                EmptyStateView(icon: "arrow.triangle.pull", title: "No pull request",
                               message: "Select a pull request to see its conversation and files.", tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.accentSecondary)
                Spacer()
                if detail.isDraft {
                    StatusPill(text: "Draft", kind: .neutral, tokens: tokens)
                }
                StatusPill(text: detail.state.capitalized,
                           kind: detail.state.lowercased() == "open" ? .open : .closedMerged, tokens: tokens)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10)).foregroundStyle(tokens.foreground.opacity(0.5))
                Text("\(detail.baseBranch) ← \(detail.headBranch)")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
            Text(statusSummary(detail))
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private func statusSummary(_ detail: PullRequestDetail) -> String {
        let mergeability: String
        switch detail.mergeable {
        case true: mergeability = "Mergeable"
        case false: mergeability = "Not mergeable (\(detail.mergeableState))"
        case nil: mergeability = "Checking mergeability…"
        }
        let checksText = model.checks.isEmpty ? "no checks" : "\(model.checks.filter { $0.conclusion == "success" }.count)/\(model.checks.count) checks passing"
        return "\(mergeability) · \(checksText) · +\(detail.additions) −\(detail.deletions)"
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabPill(.conversation, count: model.comments.count)
            tabPill(.commits, count: model.commits.count)
            tabPill(.files, count: model.files.count)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func tabPill(_ t: Tab, count: Int) -> some View {
        let isOn = tab == t
        return Button { tab = t } label: {
            HStack(spacing: 6) {
                Text(t.rawValue).font(AinkradFont.display(12, weight: .medium))
                Text("\(count)")
                    .font(AinkradFont.mono(10, weight: .medium))
                    .foregroundStyle(isOn ? tokens.accentPrimary : tokens.foreground.opacity(0.5))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill((isOn ? tokens.accentPrimary : tokens.foreground).opacity(0.12)))
            }
            .foregroundStyle(isOn ? tokens.accentPrimary : tokens.foreground.opacity(0.65))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(isOn ? tokens.accentPrimary.opacity(0.14) : .clear))
            .overlay(Capsule().strokeBorder(isOn ? tokens.accentPrimary.opacity(0.4) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation

    private func conversation(_ detail: PullRequestDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DiscussionCard(author: detail.author, timestamp: detail.createdAt,
                                   text: detail.body, isPrimary: true, tokens: tokens)
                    ForEach(model.comments) { comment in
                        DiscussionCard(author: comment.author, timestamp: comment.createdAt,
                                       text: comment.body, isPrimary: false, tokens: tokens)
                    }
                }
                .padding(16)
            }
            composer
        }
    }

    // MARK: - Commits

    private var commitsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if model.commits.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "No commits",
                                   message: "This pull request has no commits.", tokens: tokens)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(model.commits) { commit in
                        PRCommitRow(commit: commit, tokens: tokens)
                    }
                }
            }
            .padding(12)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowRule(tokens: tokens)
            HUDTextEditor(text: $composerText, placeholder: "Leave a comment…", tokens: tokens, height: 66)
            HStack(spacing: 8) {
                GMButton("Comment", kind: .secondary, systemImage: "text.bubble", tokens: tokens) {
                    Task { await model.comment(composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                GMButton("Approve", kind: .secondary, systemImage: "checkmark.seal", tokens: tokens) {
                    Task { await model.review(.approve, body: composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                GMButton("Request changes", kind: .destructive, systemImage: "exclamationmark.bubble", tokens: tokens) {
                    Task { await model.review(.requestChanges, body: composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                Spacer()
                mergeMenu
            }
        }
        .padding(16)
    }

    private var mergeMenu: some View {
        let canMerge = !(model.isLoading || model.detail?.mergeable == false)
        return HUDMenu(
            tokens: tokens,
            items: MergeMethod.allCases.map { HUDMenuItem(id: $0.rawValue, title: $0.rawValue.capitalized) },
            onPick: { raw in
                if let method = MergeMethod(rawValue: raw) { Task { await model.merge(method) } }
            }
        ) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge").font(.system(size: 10, weight: .semibold))
                Text("Merge").font(AinkradFont.display(12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(canMerge ? 0.95 : 0.5))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.accentPrimary.opacity(canMerge ? 0.9 : 0.4))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tokens.accentSecondary.opacity(0.4)))
        }
        .disabled(!canMerge)
    }

    // MARK: - Files

    private var filesTab: some View {
        FileDiffList(
            files: model.files.map { DiffFile(id: $0.filename, filename: $0.filename, status: $0.status, patch: $0.patch) },
            tokens: tokens,
            fontSize: fontSize
        )
    }
}

private struct PRCommitRow: View {
    let commit: PRCommit
    let tokens: HostThemeTokens
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(tokens.accentSecondary.opacity(0.7))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.shortSHA)
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary)
                    Text(commit.author)
                        .font(AinkradFont.display(9))
                        .foregroundStyle(tokens.foreground.opacity(0.5)).lineLimit(1)
                    Text(ForgeDate.short(commit.date))
                        .font(AinkradFont.display(9))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

