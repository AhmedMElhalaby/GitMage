import Foundation
import Combine
import AppKit
import AinkradAppKit

@MainActor
final class GitMageViewModel: ObservableObject {
    @Published var repositoryPath: String
    @Published var draftCommitMessage: String
    @Published var snapshot: GitRepositorySnapshot?
    @Published var branches: [GitBranchSummary] = []
    @Published var selectedBranchName: String = ""
    @Published var selectedChangeID: String?
    @Published var diffSnapshot: GitDiffSnapshot?
    @Published var isLoading = false
    @Published var isLoadingDiff = false
    @Published var errorMessage: String?

    private let workspaceStore: GitMageWorkspaceStore
    private let client = GitRepositoryClient()
    private let log: PluginLogger
    private var didBootstrap = false

    init(host: HostServices) {
        self.workspaceStore = GitMageWorkspaceStore(documents: host.documents)
        self.log = host.log
        let state = workspaceStore.load()
        self.repositoryPath = state.repositoryPath
        self.draftCommitMessage = state.draftCommitMessage
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard !repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        refresh()
    }

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
                snapshot = newSnapshot
                branches = newBranches
                if selectedBranchName.isEmpty || !newBranches.contains(where: { $0.name == selectedBranchName }) {
                    selectedBranchName = newSnapshot.branchName
                }
                workspaceStore.save(GitMageWorkspaceState(repositoryPath: path, draftCommitMessage: draftCommitMessage))
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
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                snapshot = nil
                branches = []
                diffSnapshot = nil
                log.error("Failed to load repository snapshot: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func chooseRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.prompt = "Choose Folder"
        panel.message = "Select the repository root folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.canResolveUbiquitousConflicts = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        repositoryPath = url.path
        saveWorkspace()
        refresh()
    }

    func checkoutSelectedBranch() {
        let branch = selectedBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.checkoutBranch(branch, in: repositoryPath)
                log.info("Checked out branch \(branch)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to checkout branch \(branch): \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

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

    func stageAllChanges() {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.stageAllChanges(in: path)
                log.info("Staged all changes in \(path)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to stage all changes: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func stageSelectedChange() {
        guard let change = selectedChange else { return }
        stage(change: change)
    }

    func stage(change: GitChange) {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.stage(change: change, in: path)
                log.info("Staged \(change.filePath) in \(path)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to stage \(change.filePath): \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func unstageSelectedChange() {
        guard let change = selectedChange else { return }
        unstage(change: change)
    }

    func unstage(change: GitChange) {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.unstage(change: change, in: path)
                log.info("Unstaged \(change.filePath) in \(path)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to unstage \(change.filePath): \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func discardSelectedChange() {
        guard let change = selectedChange else { return }
        discard(change: change)
    }

    func discard(change: GitChange) {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.discard(change: change, in: path)
                log.info("Discarded \(change.filePath) in \(path)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to discard \(change.filePath): \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func commitChanges() {
        let path = repositoryPath
        let message = draftCommitMessage
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await client.commit(message: message, in: path)
                draftCommitMessage = ""
                saveWorkspace()
                log.info("Created commit in \(path)")
                refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log.error("Failed to commit in \(path): \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    func saveWorkspace() {
        workspaceStore.save(GitMageWorkspaceState(repositoryPath: repositoryPath, draftCommitMessage: draftCommitMessage))
    }

    var selectedChange: GitChange? {
        guard let selectedChangeID else { return snapshot?.changes.first }
        return snapshot?.changes.first { $0.id == selectedChangeID }
    }

    func clearWorkspace() {
        repositoryPath = ""
        draftCommitMessage = ""
        snapshot = nil
        branches = []
        selectedBranchName = ""
        selectedChangeID = nil
        diffSnapshot = nil
        errorMessage = nil
        saveWorkspace()
    }
}
