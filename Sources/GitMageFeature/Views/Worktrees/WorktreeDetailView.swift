import SwiftUI
import AppKit
import AinkradAppKit

/// Detail pane for the selected worktree, plus the Add-worktree sheet.
struct WorktreeDetailView: View {
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens
    var fontSize: Double = 12

    private var selected: GitWorktree? {
        model.worktrees.first { $0.path == model.selectedPath }
    }

    var body: some View {
        Group {
            if let wt = selected {
                graphView(for: wt)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showAdd) {
            AddWorktreeSheet(model: model, tokens: tokens)
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "rectangle.split.3x1", title: "Worktrees",
                       message: "Select a worktree to browse its commit graph.", tokens: tokens)
    }

    // MARK: - Graph view

    private func graphView(for wt: GitWorktree) -> some View {
        VStack(spacing: 0) {
            header(for: wt)
            GlowRule(tokens: tokens)

            if model.isLoadingGraph {
                GMSpinner(tint: tokens.accentSecondary, size: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.graphRows.isEmpty {
                EmptyStateView(icon: "point.3.connected.trianglepath.dotted", title: "No history",
                               message: "This worktree has no commits yet.", tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                graphAndDiff
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(for wt: GitWorktree) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text((wt.path as NSString).lastPathComponent)
                        .font(AinkradFont.display(15, weight: .semibold))
                        .foregroundStyle(tokens.foreground)
                    if model.isCurrent(wt) {
                        Text("CURRENT")
                            .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                            .foregroundStyle(tokens.accentPrimary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(tokens.foreground.opacity(0.5))
                    Text(wt.branch ?? "detached")
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(wt.branch != nil ? tokens.accentPrimary.opacity(0.85) : tokens.foreground.opacity(0.55))
                }
            }
            Spacer()
            GMButton("Open", kind: .primary, systemImage: "arrow.up.forward.square", tokens: tokens) {
                model.open(wt)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var graphAndDiff: some View {
        let maxLanes = model.graphRows.map(\.laneCount).max() ?? 1
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.graphRows) { row in
                        GraphCommitRow(
                            row: row,
                            laneCount: maxLanes,
                            isSelected: model.selectedCommitSHA == row.commit.sha,
                            tokens: tokens,
                            onSelect: { model.selectCommit(row.commit.sha) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let diff = model.selectedCommitDiff {
                GlowRule(tokens: tokens)
                FileDiffList(files: DiffFileSplitter.split(diff.body), tokens: tokens,
                            fontSize: fontSize, fallbackTitle: diff.title)
                    .frame(height: 300)
            }
        }
    }

}

private struct AddWorktreeSheet: View {
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens
    @State private var destination: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Worktree")
                .font(AinkradFont.display(18, weight: .semibold))

            destinationPicker
            modePicker
            modeInput

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.accentTertiary.opacity(0.9))
            }

            HStack {
                Spacer()
                GMButton("Cancel", kind: .secondary, tokens: tokens) { model.showAdd = false }
                GMButton("Add", kind: .primary, systemImage: "plus", tokens: tokens) {
                    Task { await model.add(destination: destination) }
                }
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(tokens.background)
        .foregroundStyle(tokens.foreground)
    }

    private var canAdd: Bool {
        guard !destination.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch model.addMode {
        case .newBranch: return !model.addBranchName.trimmingCharacters(in: .whitespaces).isEmpty
        case .existingBranch: return !(model.addExistingBranch ?? "").isEmpty
        case .detached: return !model.addRef.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DESTINATION")
                .font(AinkradFont.display(9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            HStack(spacing: 8) {
                Text(destination.isEmpty ? "No folder chosen" : destination)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(destination.isEmpty ? 0.4 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                GMButton("Choose…", kind: .secondary, systemImage: "folder", tokens: tokens) { chooseDestination() }
            }
        }
    }

    private var modePicker: some View {
        HUDFilter(
            options: [("New branch", WorktreesViewModel.AddMode.newBranch),
                      ("Existing", WorktreesViewModel.AddMode.existingBranch),
                      ("Detached", WorktreesViewModel.AddMode.detached)],
            selection: $model.addMode, tokens: tokens
        )
    }

    @ViewBuilder private var modeInput: some View {
        switch model.addMode {
        case .newBranch:
            HUDTextField(placeholder: "Branch name", text: $model.addBranchName, tokens: tokens)
        case .existingBranch:
            HUDMenu(
                tokens: tokens,
                items: model.branchNames.map { HUDMenuItem(id: $0, title: $0, isSelected: $0 == model.addExistingBranch) },
                onPick: { model.addExistingBranch = $0 }
            ) {
                HUDMenuLabel(text: model.addExistingBranch ?? "Choose a branch",
                             isPlaceholder: model.addExistingBranch == nil, tokens: tokens)
            }
        case .detached:
            HUDTextField(placeholder: "Ref (commit, tag, branch)", text: $model.addRef, tokens: tokens)
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }
}
