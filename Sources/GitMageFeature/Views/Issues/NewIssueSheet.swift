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

            TextField("Title", text: $model.newTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $model.newBody)
                .font(AinkradFont.display(12))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                labelsMenu
                assigneesMenu
            }

            HStack {
                Spacer()
                Button("Cancel") { model.showNew = false }
                Button("Create") { Task { await model.create() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate || model.isLoading)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(tokens.background).foregroundStyle(tokens.foreground)
    }

    private var labelsMenu: some View {
        Menu {
            ForEach(model.repoLabels) { label in
                Button {
                    if model.newLabels.contains(label.name) {
                        model.newLabels.remove(label.name)
                    } else {
                        model.newLabels.insert(label.name)
                    }
                } label: {
                    if model.newLabels.contains(label.name) {
                        Label(label.name, systemImage: "checkmark")
                    } else {
                        Text(label.name)
                    }
                }
            }
        } label: {
            Label(model.newLabels.isEmpty ? "Labels" : model.newLabels.joined(separator: ", "), systemImage: "tag")
                .font(AinkradFont.display(11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var assigneesMenu: some View {
        Menu {
            ForEach(model.assignableUsers, id: \.login) { user in
                Button {
                    if model.newAssignees.contains(user.login) {
                        model.newAssignees.remove(user.login)
                    } else {
                        model.newAssignees.insert(user.login)
                    }
                } label: {
                    if model.newAssignees.contains(user.login) {
                        Label(user.login, systemImage: "checkmark")
                    } else {
                        Text(user.login)
                    }
                }
            }
        } label: {
            Label(model.newAssignees.isEmpty ? "Assignees" : model.newAssignees.joined(separator: ", "), systemImage: "person")
                .font(AinkradFont.display(11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
