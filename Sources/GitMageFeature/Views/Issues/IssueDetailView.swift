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
                        DiscussionCard(author: detail.author, timestamp: detail.createdAt,
                                       text: detail.body, isPrimary: true, tokens: tokens)
                        if !model.comments.isEmpty {
                            Text("\(model.comments.count) comment\(model.comments.count == 1 ? "" : "s")")
                                .font(AinkradFont.display(10, weight: .semibold)).kerning(1.5)
                                .foregroundStyle(tokens.foreground.opacity(0.45))
                                .padding(.top, 2)
                        }
                        ForEach(model.comments) { comment in
                            DiscussionCard(author: comment.author, timestamp: comment.createdAt,
                                           text: comment.body, isPrimary: false, tokens: tokens)
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
        // The "New Issue" modal is hosted once at the Issues area root
        // (`IssuesContextPane`), which shares this `IssuesViewModel`. Any
        // `model.showNew = true` (the context pane's "+" button, or the view
        // model itself) triggers that single modal — no duplicate here.
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
            Text("opened by \(detail.author) · \(ForgeDate.short(detail.createdAt))")
                .font(AinkradFont.mono(10))
                .foregroundStyle(tokens.foreground.opacity(0.5))
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
            AinkradTextArea(text: $composerText, placeholder: "Leave a comment…")
            HStack(spacing: 8) {
                AinkradButton(title: "Comment", style: .secondary, icon: "text.bubble") {
                    Task { await model.comment(composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                Spacer()
                if detail.state.lowercased() == "open" {
                    AinkradButton(title: "Close", style: .danger, icon: "xmark.circle") {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                } else {
                    AinkradButton(title: "Reopen", style: .primary, icon: "arrow.counterclockwise") {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .padding(16)
    }
}

/// The HUD trigger chip for the labels/assignees dropdown menus.
private struct EditorChip: View {
    let icon: String
    let title: String
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title).font(AinkradFont.display(11, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(tokens.accentPrimary.opacity(0.9))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(Capsule().strokeBorder(tokens.accentPrimary.opacity(0.2)))
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
            HUDMenu(
                tokens: tokens,
                items: model.repoLabels.map { label in
                    HUDMenuItem(id: label.name, title: label.name,
                                isSelected: detail.labels.contains { $0.name == label.name },
                                colorHex: label.color)
                },
                multiSelect: true,
                onPick: { toggle($0) }
            ) {
                EditorChip(icon: "tag", title: "Labels", tokens: tokens)
            }

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
            HUDMenu(
                tokens: tokens,
                items: model.assignableUsers.map { user in
                    HUDMenuItem(id: user.login, title: user.login,
                                isSelected: detail.assignees.contains(user.login))
                },
                multiSelect: true,
                onPick: { toggle($0) }
            ) {
                EditorChip(icon: "person", title: "Assignees", tokens: tokens)
            }

            ForEach(detail.assignees, id: \.self) { login in
                HStack(spacing: 4) {
                    ZStack {
                        Circle().fill(tokens.accentSecondary.opacity(0.2))
                        Text(String(login.prefix(1)).uppercased())
                            .font(AinkradFont.display(8, weight: .bold))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                    .frame(width: 15, height: 15)
                    Text(login)
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.75))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(0.5)))
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
