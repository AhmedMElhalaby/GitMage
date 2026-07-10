import SwiftUI
import AinkradAppKit

struct GitMageRootView: View {
    @StateObject private var model: GitMageViewModel
    let host: HostServices

    init(host: HostServices) {
        self.host = host
        _model = StateObject(wrappedValue: GitMageViewModel(host: host))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [host.theme.tokens.background, host.theme.tokens.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    repositoryEntry
                    branchSection
                    snapshotSection
                    diffSection
                    commitDraftSection
                }
                .padding(20)
                .frame(maxWidth: 920, alignment: .leading)
            }
        }
        .foregroundStyle(host.theme.tokens.foreground)
        .task { model.bootstrapIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Git Mage")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("Inspect local repositories, track changes, and stage the next commit without leaving the host.")
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.72))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(host.theme.tokens.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var repositoryEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository")
                .font(.headline)

            HStack(spacing: 10) {
                Button("Choose Folder") {
                    model.chooseRepositoryFolder()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    model.refresh()
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    model.clearWorkspace()
                }
                .buttonStyle(.bordered)

                Button("Stage All") {
                    model.stageAllChanges()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if model.repositoryPath.isEmpty {
                Text("No repository folder selected.")
                    .font(.callout)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected folder")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                    Text(model.repositoryPath)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(host.theme.tokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else {
                Text("Pick the repository root folder to load its Git state.")
                    .font(.callout)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Working Copy")
                    .font(.headline)
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if model.selectedChange != nil {
                HStack {
                    Text("Selected file")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                    Spacer()
                    Button("Stage Selected") {
                        model.stageSelectedChange()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    labelRow(title: "Root", value: snapshot.rootPath)
                    labelRow(title: "Branch", value: snapshot.branchName)
                    if let upstream = snapshot.upstream {
                        labelRow(title: "Upstream", value: upstream)
                    }
                    labelRow(title: "Last Commit", value: snapshot.headline)
                    labelRow(title: "Summary", value: snapshot.statusSummary.isEmpty ? "Clean" : snapshot.statusSummary)

                    Divider()

                    if snapshot.changes.isEmpty {
                        Text("No file changes detected.")
                            .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(snapshot.changes) { change in
                                Button {
                                    model.selectChange(change)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(change.statusCode)
                                            .font(.system(.caption, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(host.theme.tokens.accentPrimary.opacity(0.16), in: Capsule())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(change.path)
                                            Text(change.kind.label)
                                                .font(.caption)
                                                .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(10)
                                .background(
                                    model.selectedChangeID == change.id
                                    ? host.theme.tokens.accentPrimary.opacity(0.12)
                                    : host.theme.tokens.surface.opacity(0.34),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                        }
                    }
                }
            } else {
                Text("Load a repository to inspect its branch, commit, and file status.")
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Branches")
                .font(.headline)

            if model.branches.isEmpty {
                Text("No local branches loaded yet.")
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
            } else {
                Picker("Branch", selection: $model.selectedBranchName) {
                    ForEach(model.branches) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 10) {
                    Button("Checkout Branch") {
                        model.checkoutSelectedBranch()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Pick a target branch, then checkout to update the working copy.")
                        .font(.callout)
                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.branches) { branch in
                        Button {
                            model.selectedBranchName = branch.name
                        } label: {
                            HStack(spacing: 10) {
                                Text(branch.isCurrent ? "●" : "○")
                                    .foregroundStyle(branch.isCurrent ? host.theme.tokens.accentPrimary : host.theme.tokens.foreground.opacity(0.42))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(branch.name)
                                    Text(branch.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diff")
                    .font(.headline)
                Spacer()
                if model.isLoadingDiff {
                    ProgressView().controlSize(.small)
                }
            }

            if let diff = model.diffSnapshot {
                Text(diff.title)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))

                ScrollView(.vertical) {
                    Text(diff.body)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220, maxHeight: 360)
                .padding(12)
                .background(host.theme.tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text("Select a file to inspect its diff.")
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var commitDraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Commit Draft")
                    .font(.headline)
                Spacer()
                Button("Commit") {
                    model.commitChanges()
                }
                .buttonStyle(.borderedProminent)
            }

            TextEditor(text: $model.draftCommitMessage)
                .frame(minHeight: 110)
                .padding(8)
                .background(host.theme.tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("The commit flow will wire in after the read-only inspection slice lands.")
                    .font(.callout)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                Spacer()
                Button("Save Draft") {
                    model.saveWorkspace()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func labelRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }
}
