import SwiftUI
import AinkradAppKit

/// Detail pane for the Issues area: header, editable labels/assignees, body,
/// comments, and a composer with close/reopen.
struct IssueDetailView: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens

    @State private var composerText = ""

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(detail)
                        editors(detail)
                        if !detail.body.isEmpty {
                            MarkdownText(markdown: detail.body, tokens: tokens)
                        }
                        ForEach(model.comments) { comment in
                            IssueCommentRow(comment: comment, tokens: tokens)
                        }
                    }
                    .padding(16)
                }
                composer(detail)
            } else {
                EmptyStateView(icon: "smallcircle.filled.circle", title: "No issue",
                               message: "Select an issue to read and respond to it.", tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showNew) {
            NewIssueSheet(model: model, tokens: tokens)
        }
    }

    private func header(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.accentSecondary)
                Spacer()
                StatusPill(text: detail.state.lowercased() == "open" ? "Open" : "Closed",
                           kind: detail.state.lowercased() == "open" ? .open : .closedMerged, tokens: tokens)
            }
            Text(detail.author)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
    }

    private func editors(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelsEditor(model: model, detail: detail, tokens: tokens)
            AssigneesEditor(model: model, detail: detail, tokens: tokens)
        }
    }

    private func composer(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowRule(tokens: tokens)
            HUDTextEditor(text: $composerText, placeholder: "Leave a comment…", tokens: tokens, height: 66)
            HStack(spacing: 8) {
                GMButton("Comment", kind: .secondary, systemImage: "text.bubble", tokens: tokens) {
                    Task { await model.comment(composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                Spacer()
                if detail.state.lowercased() == "open" {
                    GMButton("Close", kind: .destructive, systemImage: "xmark.circle", tokens: tokens) {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                } else {
                    GMButton("Reopen", kind: .primary, systemImage: "arrow.counterclockwise", tokens: tokens) {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .padding(16)
    }
}

private struct IssueCommentRow: View {
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
            MarkdownText(markdown: comment.body, tokens: tokens)
        }
        .padding(10)
        .background(tokens.surfaceElevated.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Editable labels control: a menu of repo labels with checkmarks on those
/// currently applied, rendering colored chips for the current selection.
private struct LabelsEditor: View {
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(model.repoLabels) { label in
                    Button {
                        toggle(label.name)
                    } label: {
                        if detail.labels.contains(where: { $0.name == label.name }) {
                            Label(label.name, systemImage: "checkmark")
                        } else {
                            Text(label.name)
                        }
                    }
                }
            } label: {
                Label("Labels", systemImage: "tag")
                    .font(AinkradFont.display(11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            ForEach(detail.labels) { label in
                ColoredLabelChip(label: label)
            }
        }
    }

    private func toggle(_ name: String) {
        var names = Set(detail.labels.map(\.name))
        if names.contains(name) {
            names.remove(name)
        } else {
            names.insert(name)
        }
        Task { await model.setLabels(names) }
    }
}

/// Editable assignees control: a menu of assignable users with checkmarks on
/// those currently assigned.
private struct AssigneesEditor: View {
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(model.assignableUsers, id: \.login) { user in
                    Button {
                        toggle(user.login)
                    } label: {
                        if detail.assignees.contains(user.login) {
                            Label(user.login, systemImage: "checkmark")
                        } else {
                            Text(user.login)
                        }
                    }
                }
            } label: {
                Label("Assignees", systemImage: "person")
                    .font(AinkradFont.display(11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !detail.assignees.isEmpty {
                Text(detail.assignees.joined(separator: ", "))
                    .font(AinkradFont.mono(10))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
        }
    }

    private func toggle(_ login: String) {
        var logins = Set(detail.assignees)
        if logins.contains(login) {
            logins.remove(login)
        } else {
            logins.insert(login)
        }
        Task { await model.setAssignees(logins) }
    }
}
