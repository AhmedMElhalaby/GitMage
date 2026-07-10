import Foundation
import Combine
import AppKit
import AinkradAppKit

@MainActor
final class GitMageViewModel: ObservableObject {
    // Library
    @Published var repos: [GitMageRepoConfig] = []
    @Published var activeRepoID: String?

    // Active-repo editors / transient state
    @Published var draftCommitMessage: String = ""
    @Published var newBranchName: String = ""
    @Published var snapshot: GitRepositorySnapshot?
    @Published var branches: [GitBranchSummary] = []
    @Published var stashes: [GitStashEntry] = []
    @Published var selectedBranchName: String = ""
    @Published var selectedChangeID: String?
    @Published var diffSnapshot: GitDiffSnapshot?
    @Published var isLoading = false
    @Published var isLoadingDiff = false
    @Published var errorMessage: String?

    // Prompts driven from the view
    @Published var pendingInitPath: String?
    @Published var showInitPrompt = false
    @Published var showClonePrompt = false
    @Published var cloneRemoteURL = ""

    private let workspaceStore: GitMageWorkspaceStore
    private let client = GitRepositoryClient()
    private let log: PluginLogger
    private var didBootstrap = false

    init(host: HostServices) {
        self.workspaceStore = GitMageWorkspaceStore(documents: host.documents)
        self.log = host.log
        let library = workspaceStore.loadLibrary()
        self.repos = library.repos
        self.activeRepoID = library.activeRepoID ?? library.repos.first?.id
        loadActiveRepoIntoEditors()
    }

    // MARK: - Active repo

    var activeRepo: GitMageRepoConfig? {
        guard let activeRepoID else { return nil }
        return repos.first { $0.id == activeRepoID }
    }

    var repositoryPath: String { activeRepo?.path ?? "" }
    var hasActiveRepo: Bool { !repositoryPath.isEmpty }

    private func loadActiveRepoIntoEditors() {
        let repo = activeRepo
        draftCommitMessage = repo?.draftCommitMessage ?? ""
        selectedBranchName = repo?.lastBranch ?? ""
        selectedChangeID = repo?.lastSelectedFileID
    }

    private func resetTransientState() {
        snapshot = nil
        branches = []
        stashes = []
        diffSnapshot = nil
        errorMessage = nil
    }

    /// Folds the live editor state back into the active repo config.
    private func syncActiveRepoState() {
        guard let activeRepoID,
              let index = repos.firstIndex(where: { $0.id == activeRepoID }) else { return }
        repos[index].draftCommitMessage = draftCommitMessage
        repos[index].lastBranch = selectedBranchName
        repos[index].lastSelectedFileID = selectedChangeID
    }

    private func persistLibrary() {
        syncActiveRepoState()
        workspaceStore.saveLibrary(GitMageLibraryState(repos: repos, activeRepoID: activeRepoID))
    }

    func saveDraft() {
        persistLibrary()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard hasActiveRepo else { return }
        refresh()
    }

    // MARK: - Library management

    func addRepositoryFolder() {
        guard let url = pickFolder(
            title: "Add a Git Repository",
            prompt: "Add Repository",
            message: "Select a repository root folder."
        ) else { return }
        let path = url.path

        Task { @MainActor in
            if await client.isRepository(at: path) {
                registerRepository(path: path)
            } else {
                pendingInitPath = path
                showInitPrompt = true
            }
        }
    }

    func confirmInitPendingRepository() {
        guard let path = pendingInitPath else { return }
        pendingInitPath = nil
        Task { @MainActor in
            do {
                try await client.initRepository(at: path)
                log.info("Initialized new repository at \(path)")
                registerRepository(path: path)
            } catch {
                report(error, context: "initialize repository at \(path)")
            }
        }
    }

    func cancelInitPendingRepository() {
        pendingInitPath = nil
    }

    func startClone() {
        cloneRemoteURL = ""
        showClonePrompt = true
    }

    func performClone() {
        let remote = cloneRemoteURL
        guard !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = GitRepositoryError.invalidRemoteURL.errorDescription
            return
        }
        guard let parent = pickFolder(
            title: "Choose a Destination Folder",
            prompt: "Clone Here",
            message: "Select the folder to clone the repository into."
        ) else { return }

        isLoading = true
        errorMessage = nil
        showClonePrompt = false

        Task { @MainActor in
            do {
                let destination = try await client.clone(remoteURL: remote, into: parent.path)
                cloneRemoteURL = ""
                log.info("Cloned \(remote) into \(destination)")
                registerRepository(path: destination)
            } catch {
                isLoading = false
                report(error, context: "clone \(remote)")
            }
        }
    }

    /// Adds (or re-selects) a repo, makes it active, and loads it.
    private func registerRepository(path: String) {
        syncActiveRepoState()

        if let existing = repos.first(where: { $0.path == path }) {
            activeRepoID = existing.id
        } else {
            let repo = GitMageRepoConfig(
                id: UUID().uuidString,
                path: path,
                name: (path as NSString).lastPathComponent
            )
            repos.append(repo)
            activeRepoID = repo.id
        }

        resetTransientState()
        loadActiveRepoIntoEditors()
        persistLibrary()
        refresh()
    }

    func selectRepository(_ id: String) {
        guard id != activeRepoID else { return }
        syncActiveRepoState()
        persistLibrary()

        activeRepoID = id
        resetTransientState()
        loadActiveRepoIntoEditors()
        refresh()
    }

    func removeActiveRepository() {
        guard let activeRepoID else { return }
        removeRepository(activeRepoID)
    }

    func removeRepository(_ id: String) {
        repos.removeAll { $0.id == id }
        if activeRepoID == id {
            activeRepoID = repos.first?.id
            resetTransientState()
            loadActiveRepoIntoEditors()
        }
        persistLibrary()
        if hasActiveRepo { refresh() }
    }

    // MARK: - Snapshot / refresh

    func refresh() {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = GitRepositoryError.missingPath.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let newSnapshot = try await client.loadSnapshot(at: path)
                let newBranches = (try? await client.loadBranches(at: path)) ?? []
                let newStashes = (try? await client.loadStashes(in: path)) ?? []
                snapshot = newSnapshot
                branches = newBranches
                stashes = newStashes
                if selectedBranchName.isEmpty || !newBranches.contains(where: { $0.name == selectedBranchName }) {
                    selectedBranchName = newSnapshot.branchName
                }
                persistLibrary()
                log.info("Loaded repository snapshot for \(path)")
                isLoading = false
                if let selectedChangeID,
                   let existingChange = newSnapshot.changes.first(where: { $0.id == selectedChangeID }) {
                    selectChange(existingChange)
                } else if let firstChange = newSnapshot.changes.first {
                    selectedChangeID = firstChange.id
                    selectChange(firstChange)
                } else {
                    selectedChangeID = nil
                    diffSnapshot = nil
                }
            } catch {
                snapshot = nil
                branches = []
                stashes = []
                diffSnapshot = nil
                isLoading = false
                report(error, context: "load repository snapshot")
            }
        }
    }

    // MARK: - Branches

    func checkoutSelectedBranch() {
        let branch = selectedBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return }
        run(context: "checkout branch \(branch)") { [self] in
            try await client.checkoutBranch(branch, in: repositoryPath)
        }
    }

    func createBranch() {
        let name = newBranchName
        run(context: "create branch \(name)") { [self] in
            try await client.createBranch(name, in: repositoryPath)
            newBranchName = ""
        }
    }

    // MARK: - Remote operations

    func fetch() {
        run(context: "fetch") { [self] in try await client.fetch(in: repositoryPath) }
    }

    func pull() {
        run(context: "pull") { [self] in try await client.pull(in: repositoryPath) }
    }

    func push() {
        run(context: "push") { [self] in try await client.push(in: repositoryPath) }
    }

    // MARK: - Stash

    func stashChanges() {
        run(context: "stash changes") { [self] in try await client.stashPush(in: repositoryPath) }
    }

    func popLatestStash() {
        run(context: "pop stash") { [self] in try await client.stashPop(in: repositoryPath) }
    }

    func applyStash(_ entry: GitStashEntry) {
        run(context: "apply \(entry.id)") { [self] in try await client.stashApply(entry, in: repositoryPath) }
    }

    func dropStash(_ entry: GitStashEntry) {
        run(context: "drop \(entry.id)") { [self] in try await client.stashDrop(entry, in: repositoryPath) }
    }

    // MARK: - Diff

    func selectChange(_ change: GitChange) {
        selectedChangeID = change.id
        loadDiff(for: change)
    }

    func loadDiff(for change: GitChange) {
        let path = repositoryPath
        isLoadingDiff = true
        Task { @MainActor in
            do {
                let diff = try await client.loadDiff(for: change, in: path)
                diffSnapshot = diff
                isLoadingDiff = false
            } catch {
                diffSnapshot = GitDiffSnapshot(
                    title: change.path,
                    body: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    isEmpty: true
                )
                isLoadingDiff = false
                log.error("Failed to load diff for \(change.filePath): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Staging

    func stageAllChanges() {
        run(context: "stage all changes") { [self] in try await client.stageAllChanges(in: repositoryPath) }
    }

    func stageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "stage \(change.filePath)") { [self] in try await client.stage(change: change, in: repositoryPath) }
    }

    func unstageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "unstage \(change.filePath)") { [self] in try await client.unstage(change: change, in: repositoryPath) }
    }

    func discardSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "discard \(change.filePath)") { [self] in try await client.discard(change: change, in: repositoryPath) }
    }

    func commitChanges() {
        let message = draftCommitMessage
        run(context: "commit") { [self] in
            try await client.commit(message: message, in: repositoryPath)
            draftCommitMessage = ""
            persistLibrary()
        }
    }

    var selectedChange: GitChange? {
        guard let selectedChangeID else { return snapshot?.changes.first }
        return snapshot?.changes.first { $0.id == selectedChangeID }
    }

    // MARK: - Helpers

    /// Runs a mutating git action, then refreshes on success or reports on failure.
    private func run(context: String, _ action: @escaping () async throws -> Void) {
        guard hasActiveRepo else { return }
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await action()
                log.info("Completed \(context) in \(repositoryPath)")
                refresh()
            } catch {
                isLoading = false
                report(error, context: context)
            }
        }
    }

    private func report(_ error: Error, context: String) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        log.error("Failed to \(context): \(error.localizedDescription)")
    }

    private func pickFolder(title: String, prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.canResolveUbiquitousConflicts = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
