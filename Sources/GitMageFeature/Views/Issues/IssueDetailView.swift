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
                            Text(detail.body)
                                .font(AinkradFont.display(12))
                                .foregroundStyle(tokens.foreground.opacity(0.85))
                                .textSelection(.enabled)
                        }
                        ForEach(model.comments) { comment in
                            IssueCommentRow(comment: comment, tokens: tokens)
                        }
                    }
                    .padding(16)
                }
                composer(detail)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showNew) {
            NewIssueSheet(model: model, tokens: tokens)
        }
    }

    private var placeholder: some View {
        VStack {
            Text("Select an issue.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                statePill(detail.state)
                Spacer()
            }
            Text(detail.author)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
    }

    private func statePill(_ state: String) -> some View {
        let isOpen = state == "open"
        return Text(isOpen ? "Open" : "Closed")
            .font(AinkradFont.display(9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                (isOpen ? tokens.accentPrimary : tokens.foreground.opacity(0.4)).opacity(0.85),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }

    private func editors(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelsEditor(model: model, detail: detail, tokens: tokens)
            AssigneesEditor(model: model, detail: detail, tokens: tokens)
        }
    }

    private func composer(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $composerText)
                .font(AinkradFont.display(12))
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 8) {
                actionButton("Comment") { Task { await model.comment(composerText); composerText = "" } }
                Spacer()
                actionButton(detail.state == "open" ? "Close" : "Reopen") {
                    Task { await model.toggleState() }
                }
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
            Text(comment.body)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .textSelection(.enabled)
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
                        Label(label.name, systemImage: detail.labels.contains { $0.name == label.name } ? "checkmark" : "")
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
                        Label(user.login, systemImage: detail.assignees.contains(user.login) ? "checkmark" : "")
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
