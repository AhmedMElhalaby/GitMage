import SwiftUI
import AppKit
import AinkradAppKit

/// Detail pane for the selected worktree, plus the Add-worktree sheet.
struct WorktreeDetailView: View {
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens

    private var selected: GitWorktree? {
        model.worktrees.first { $0.path == model.selectedPath }
    }

    var body: some View {
        Group {
            if let wt = selected {
                summary(for: wt)
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
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.5))
            Text("Select a worktree.")
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
    }

    private func summary(for wt: GitWorktree) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((wt.path as NSString).lastPathComponent)
                .font(AinkradFont.display(18, weight: .semibold))
            infoRow(label: "Path", value: wt.path, mono: true)
            infoRow(label: "HEAD", value: wt.head, mono: true)
            infoRow(label: "Branch", value: wt.branch ?? "detached")
            infoRow(label: "Status", value: statusText(for: wt))
            Button("Open in Git Mage") { model.open(wt) }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func statusText(for wt: GitWorktree) -> String {
        var pieces: [String] = []
        if wt.isLocked { pieces.append("locked") }
        if wt.isPrunable { pieces.append("prunable") }
        if wt.isBare { pieces.append("bare") }
        return pieces.isEmpty ? "clean" : pieces.joined(separator: " · ")
    }

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(AinkradFont.display(9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            Text(value)
                .font(mono ? AinkradFont.mono(12) : AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
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
                    .foregroundStyle(.red.opacity(0.85))
            }

            HStack {
                Spacer()
                Button("Cancel") { model.showAdd = false }
                Button("Add") { Task { await model.add(destination: destination) } }
                    .buttonStyle(.borderedProminent)
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
                Button("Choose…") { chooseDestination() }
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $model.addMode) {
            Text("New branch").tag(WorktreesViewModel.AddMode.newBranch)
            Text("Existing branch").tag(WorktreesViewModel.AddMode.existingBranch)
            Text("Detached").tag(WorktreesViewModel.AddMode.detached)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder private var modeInput: some View {
        switch model.addMode {
        case .newBranch:
            TextField("Branch name", text: $model.addBranchName)
                .textFieldStyle(.roundedBorder)
        case .existingBranch:
            Menu {
                ForEach(model.branchNames, id: \.self) { name in
                    Button(name) { model.addExistingBranch = name }
                }
            } label: {
                Text(model.addExistingBranch ?? "Choose a branch")
                    .font(AinkradFont.display(12))
            }
        case .detached:
            TextField("Ref (commit, tag, branch)", text: $model.addRef)
                .textFieldStyle(.roundedBorder)
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
