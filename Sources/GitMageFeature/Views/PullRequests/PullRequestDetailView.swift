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
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                header(detail)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16).padding(.vertical, 10)

                switch tab {
                case .conversation:
                    conversation(detail)
                case .files:
                    filesTab
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack {
            Text("Select a pull request.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                if detail.isDraft {
                    Text("Draft")
                        .font(AinkradFont.display(9, weight: .semibold))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(tokens.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Spacer()
            }
            Text("\(detail.baseBranch) ← \(detail.headBranch)")
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.55))
            Text(statusSummary(detail))
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.top, 14)
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

    // MARK: - Conversation

    private func conversation(_ detail: PullRequestDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !detail.body.isEmpty {
                        Text(detail.body)
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.foreground.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    ForEach(model.comments) { comment in
                        CommentRow(comment: comment, tokens: tokens)
                    }
                }
                .padding(16)
            }
            composer
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $composerText)
                .font(AinkradFont.display(12))
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 8) {
                actionButton("Comment") { Task { await model.comment(composerText); composerText = "" } }
                actionButton("Approve") { Task { await model.review(.approve, body: composerText); composerText = "" } }
                actionButton("Request changes") { Task { await model.review(.requestChanges, body: composerText); composerText = "" } }
                Spacer()
                mergeMenu
            }
        }
        .padding(16)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AinkradFont.display(12, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.2)))
        .disabled(model.isLoading)
    }

    private var mergeMenu: some View {
        Menu {
            ForEach(MergeMethod.allCases, id: \.self) { method in
                Button(method.rawValue.capitalized) { Task { await model.merge(method) } }
            }
        } label: {
            Text("Merge").font(AinkradFont.display(12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tokens.accentPrimary.opacity(model.detail?.mergeable == false ? 0.08 : 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(model.isLoading || model.detail?.mergeable == false)
    }

    // MARK: - Files

    private var filesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.files) { file in
                    DiffView(
                        diff: GitDiffSnapshot(
                            title: file.filename,
                            body: file.patch ?? "Binary file or no patch available.",
                            isEmpty: file.patch == nil
                        ),
                        tokens: tokens,
                        fontSize: fontSize
                    )
                    .frame(minHeight: 160)
                }
            }
        }
    }
}

private struct CommentRow: View {
    let comment: ForgeComment
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author)
                    .font(AinkradFont.display(11, weight: .semibold))
                Text(comment.createdAt)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
            Text(comment.body)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(10)
        .background(tokens.surfaceElevated.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
