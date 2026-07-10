import Foundation
import Combine
import AppKit
import AinkradAppKit

@MainActor
final class GitMageViewModel: ObservableObject {
    @Published var repositoryPath: String
    @Published var draftCommitMessage: String
    @Published var snapshot: GitRepositorySnapshot?
    @Published var isLoading = false
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
                snapshot = newSnapshot
                workspaceStore.save(GitMageWorkspaceState(repositoryPath: path, draftCommitMessage: draftCommitMessage))
                log.info("Loaded repository snapshot for \(path)")
                isLoading = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                snapshot = nil
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

    func saveWorkspace() {
        workspaceStore.save(GitMageWorkspaceState(repositoryPath: repositoryPath, draftCommitMessage: draftCommitMessage))
    }

    func clearWorkspace() {
        repositoryPath = ""
        draftCommitMessage = ""
        snapshot = nil
        errorMessage = nil
        saveWorkspace()
    }
}
