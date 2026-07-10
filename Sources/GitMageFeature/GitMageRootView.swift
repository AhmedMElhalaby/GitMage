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
                    repositoryLibrary
                    if model.hasActiveRepo {
                        remoteSection
                        branchSection
                        snapshotSection
                        diffSection
                        stashSection
                        commitDraftSection
                    }
                }
                .padding(20)
                .frame(maxWidth: 920, alignment: .leading)
            }
        }
        .foregroundStyle(host.theme.tokens.foreground)
        .task { model.bootstrapIfNeeded() }
        .alert("Initialize a new Git repository?", isPresented: $model.showInitPrompt) {
            Button("Cancel", role: .cancel) { model.cancelInitPendingRepository() }
            Button("Initialize") { model.confirmInitPendingRepository() }
        } message: {
            Text("\(model.pendingInitPath ?? "") is not a Git repository yet. Initialize it and add it to your library?")
        }
        .sheet(isPresented: $model.showClonePrompt) { cloneSheet }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Git Mage")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("Manage your repositories, track changes, and drive the common Git workflows without leaving the host.")
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.72))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(host.theme.tokens.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Repository library

    private var repositoryLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repositories")
                    .font(.headline)
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Button("Add…") { model.addRepositoryFolder() }
                    .buttonStyle(.borderedProminent)
                Button("Clone…") { model.startClone() }
                    .buttonStyle(.bordered)
                if model.hasActiveRepo {
                    Button("Refresh") { model.refresh() }
                        .buttonStyle(.bordered)
                    Button("Remove") { model.removeActiveRepository() }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }

            if model.repos.isEmpty {
                Text("No repositories yet. Add a local folder or clone one to get started.")
                    .font(.callout)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.repos) { repo in
                        Button {
                            model.selectRepository(repo.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: repo.id == model.activeRepoID ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(repo.id == model.activeRepoID
                                                     ? host.theme.tokens.accentPrimary
                                                     : host.theme.tokens.foreground.opacity(0.42))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.name)
                                    Text(repo.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(
                            repo.id == model.activeRepoID
                            ? host.theme.tokens.accentPrimary.opacity(0.12)
                            : host.theme.tokens.surface.opacity(0.34),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Remote operations

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote")
                .font(.headline)
            HStack(spacing: 10) {
                Button("Fetch") { model.fetch() }
                    .buttonStyle(.bordered)
                Button("Pull") { model.pull() }
                    .buttonStyle(.bordered)
                Button("Push") { model.push() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            Text("Pull is fast-forward only. Push sets origin as upstream for new branches.")
                .font(.callout)
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Branches

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Branches")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("New branch name", text: $model.newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button("Create Branch") { model.createBranch() }
                    .buttonStyle(.bordered)
                    .disabled(model.newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }

            if model.branches.isEmpty {
                Text("No local branches loaded yet.")
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
            } else {
                HStack(spacing: 10) {
                    Picker("Branch", selection: $model.selectedBranchName) {
                        ForEach(model.branches) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button("Checkout") { model.checkoutSelectedBranch() }
                        .buttonStyle(.borderedProminent)
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

    // MARK: - Working copy

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Working Copy")
                    .font(.headline)
                Spacer()
                Button("Stage All") { model.stageAllChanges() }
                    .buttonStyle(.bordered)
            }

            if model.selectedChange != nil {
                HStack {
                    Text("Selected file")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                    Spacer()
                    if model.selectedChange?.canUnstage == true {
                        Button("Unstage") { model.unstageSelectedChange() }
                            .buttonStyle(.bordered)
                    }
                    Button("Discard") { model.discardSelectedChange() }
                        .buttonStyle(.bordered)
                    Button("Stage Selected") { model.stageSelectedChange() }
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

    // MARK: - Diff

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

    // MARK: - Stash

    private var stashSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stashes")
                    .font(.headline)
                Spacer()
                Button("Stash Changes") { model.stashChanges() }
                    .buttonStyle(.bordered)
                Button("Pop Latest") { model.popLatestStash() }
                    .buttonStyle(.bordered)
                    .disabled(model.stashes.isEmpty)
            }

            if model.stashes.isEmpty {
                Text("No stashes saved.")
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.64))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.stashes) { stash in
                        HStack(spacing: 10) {
                            Text(stash.id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                            Text(stash.message)
                            Spacer()
                            Button("Apply") { model.applyStash(stash) }
                                .buttonStyle(.bordered)
                            Button("Drop") { model.dropStash(stash) }
                                .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(host.theme.tokens.surface.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Commit

    private var commitDraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Commit Draft")
                    .font(.headline)
                Spacer()
                Button("Commit") { model.commitChanges() }
                    .buttonStyle(.borderedProminent)
            }

            TextEditor(text: $model.draftCommitMessage)
                .frame(minHeight: 110)
                .padding(8)
                .background(host.theme.tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("Write a commit message for the staged changes, then commit or save the draft for later.")
                    .font(.callout)
                    .foregroundStyle(host.theme.tokens.foreground.opacity(0.58))
                Spacer()
                Button("Save Draft") { model.saveDraft() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(host.theme.tokens.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Clone sheet

    private var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone a Repository")
                .font(.title2.weight(.semibold))
            Text("Enter a Git remote URL. You'll then choose a destination folder to clone into.")
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.72))
            TextField("https://github.com/owner/repo.git", text: $model.cloneRemoteURL)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 380)
            HStack {
                Spacer()
                Button("Cancel") { model.showClonePrompt = false }
                    .buttonStyle(.bordered)
                Button("Choose Destination & Clone") { model.performClone() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.cloneRemoteURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(host.theme.tokens.background)
        .foregroundStyle(host.theme.tokens.foreground)
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
