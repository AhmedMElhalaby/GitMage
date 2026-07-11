import SwiftUI
import AinkradAppKit

/// Detail pane for the selected Advanced op: rebase, cherry-pick, revert, reset, tags.
struct AdvancedDetailView: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        Group {
            switch model.selectedOp {
            case .rebase:
                RebasePane(model: model, tokens: tokens)
            case .cherryPick:
                CherryPickRevertPane(model: model, tokens: tokens, mode: .cherryPick)
            case .revert:
                CherryPickRevertPane(model: model, tokens: tokens, mode: .revert)
            case .reset:
                ResetPane(model: model, tokens: tokens)
            case .tags:
                TagsPane(model: model, tokens: tokens)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .alert(item: $model.pendingConfirm) { pending in
            Alert(
                title: Text(pending.title),
                message: Text(pending.message),
                primaryButton: .default(Text("Confirm")) { Task { await model.confirmPending() } },
                secondaryButton: .cancel(Text("Cancel")) { model.cancelPending() }
            )
        }
    }
}

// MARK: - Rebase

private struct RebasePane: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rebase")
                .font(AinkradFont.display(18, weight: .semibold))

            fieldLabel("ONTO BRANCH")
            Menu {
                ForEach(model.branchNames, id: \.self) { name in
                    Button(name) { model.rebaseBase = name }
                }
            } label: {
                Text(model.rebaseBase ?? "Choose a branch")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
            }

            Toggle("Auto-stash uncommitted changes", isOn: $model.autostash)
                .font(AinkradFont.display(12))

            Button("Rebase") { model.requestRebase() }
                .font(AinkradFont.display(12, weight: .medium))
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.rebaseBase == nil || model.rebaseBase?.isEmpty == true)

            Spacer()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(9, weight: .semibold))
            .foregroundStyle(tokens.foreground.opacity(0.45))
    }
}

// MARK: - Cherry-pick / Revert

private struct CherryPickRevertPane: View {
    enum Mode { case cherryPick, revert }

    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens
    let mode: Mode

    private var title: String { mode == .cherryPick ? "Cherry-pick" : "Revert" }
    private var actionTitle: String { mode == .cherryPick ? "Apply" : "Revert" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AinkradFont.display(18, weight: .semibold))

            CommitListView(model: model, tokens: tokens)

            Button(actionTitle) {
                Task {
                    if mode == .cherryPick {
                        await model.cherryPick()
                    } else {
                        await model.revert()
                    }
                }
            }
            .font(AinkradFont.display(12, weight: .medium))
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || model.selectedCommit == nil)
        }
    }
}

// MARK: - Reset

private struct ResetPane: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reset")
                .font(AinkradFont.display(18, weight: .semibold))

            CommitListView(model: model, tokens: tokens)

            Picker("", selection: $model.resetMode) {
                ForEach(ResetMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Toggle("Auto-stash uncommitted changes", isOn: $model.autostash)
                .font(AinkradFont.display(12))

            Button("Reset") { model.requestReset() }
                .font(AinkradFont.display(12, weight: .medium))
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.selectedCommit == nil)
        }
    }
}

// MARK: - Shared commit list

private struct CommitListView: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if model.commits.isEmpty {
                    Text("No commits.")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .padding(12)
                }
                ForEach(model.commits) { commit in
                    CommitRow(
                        commit: commit,
                        tokens: tokens,
                        isSelected: model.selectedCommit == commit.id,
                        onSelect: { model.selectedCommit = commit.id }
                    )
                }
            }
        }
        .frame(maxHeight: 320)
        .background(tokens.surfaceElevated.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CommitRow: View {
    let commit: GitCommitSummary
    let tokens: HostThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(AinkradFont.display(12)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.shortSHA).font(AinkradFont.mono(9)).foregroundStyle(tokens.accentSecondary)
                    Text(commit.author).font(AinkradFont.display(9)).foregroundStyle(tokens.foreground.opacity(0.5))
                    Text(commit.relativeDate).font(AinkradFont.display(9)).foregroundStyle(tokens.foreground.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, 4)
    }
}

// MARK: - Tags

private struct TagsPane: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tags")
                .font(AinkradFont.display(18, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if model.tags.isEmpty {
                        Text("No tags.")
                            .font(AinkradFont.display(12))
                            .foregroundStyle(tokens.foreground.opacity(0.5))
                            .padding(8)
                    }
                    ForEach(model.tags) { tag in
                        TagRow(tag: tag, tokens: tokens) {
                            Task { await model.deleteTag(tag.name) }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(tokens.surfaceElevated.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            createForm
            Spacer()
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEW TAG")
                .font(AinkradFont.display(9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            TextField("Tag name", text: $model.newTagName)
                .textFieldStyle(.roundedBorder).font(AinkradFont.display(12))
            TextField("Message (optional)", text: $model.newTagMessage)
                .textFieldStyle(.roundedBorder).font(AinkradFont.display(12))
            Button("Create") { Task { await model.createTag() } }
                .font(AinkradFont.display(12, weight: .medium))
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct TagRow: View {
    let tag: GitTag
    let tokens: HostThemeTokens
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name).font(AinkradFont.display(12, weight: .medium))
                if let message = tag.message, !message.isEmpty {
                    Text(message)
                        .font(AinkradFont.display(10))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(tokens.foreground.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
