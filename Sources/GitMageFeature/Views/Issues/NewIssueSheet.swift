import SwiftUI
import AinkradAppKit

/// Sheet for composing a new issue: title, body, and optional labels/assignees.
struct NewIssueSheet: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens

    private var canCreate: Bool {
        !model.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Issue").font(AinkradFont.display(18, weight: .semibold))

            HUDTextField(placeholder: "Title", text: $model.newTitle, tokens: tokens)

            HUDTextEditor(text: $model.newBody, placeholder: "Description…", tokens: tokens, height: 120)

            HStack(spacing: 10) {
                labelsMenu
                assigneesMenu
            }

            HStack {
                Spacer()
                GMButton("Cancel", kind: .secondary, tokens: tokens) { model.showNew = false }
                GMButton("Create", kind: .primary, tokens: tokens) { Task { await model.create() } }
                    .disabled(!canCreate || model.isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tokens.foreground)
    }

    private var labelsMenu: some View {
        HUDMenu(
            tokens: tokens,
            items: model.repoLabels.map { label in
                HUDMenuItem(id: label.name, title: label.name,
                            isSelected: model.newLabels.contains(label.name), colorHex: label.color)
            },
            multiSelect: true,
            onPick: { name in
                if model.newLabels.contains(name) { model.newLabels.remove(name) }
                else { model.newLabels.insert(name) }
            }
        ) {
            HUDMenuLabel(text: model.newLabels.isEmpty ? "Labels" : model.newLabels.sorted().joined(separator: ", "),
                         isPlaceholder: model.newLabels.isEmpty, tokens: tokens)
        }
    }

    private var assigneesMenu: some View {
        HUDMenu(
            tokens: tokens,
            items: model.assignableUsers.map { user in
                HUDMenuItem(id: user.login, title: user.login, isSelected: model.newAssignees.contains(user.login))
            },
            multiSelect: true,
            onPick: { login in
                if model.newAssignees.contains(login) { model.newAssignees.remove(login) }
                else { model.newAssignees.insert(login) }
            }
        ) {
            HUDMenuLabel(text: model.newAssignees.isEmpty ? "Assignees" : model.newAssignees.sorted().joined(separator: ", "),
                         isPlaceholder: model.newAssignees.isEmpty, tokens: tokens)
        }
    }
}
