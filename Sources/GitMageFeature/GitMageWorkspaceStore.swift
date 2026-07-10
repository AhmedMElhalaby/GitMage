import Foundation
import AinkradAppKit

struct GitMageWorkspaceStore {
    private let documents: PluginDocumentStore
    private let legacyKey = "workspace.state.v1"
    private let libraryKey = "library.state.v2"

    init(documents: PluginDocumentStore) {
        self.documents = documents
    }

    // MARK: - Library (v2)

    /// Loads the repo library, migrating a legacy single-repo install on first run.
    func loadLibrary() -> GitMageLibraryState {
        if let data = documents.data(forKey: libraryKey),
           let library = try? JSONDecoder().decode(GitMageLibraryState.self, from: data) {
            return library
        }

        let migrated = migrateLegacyIfPresent()
        if let migrated {
            saveLibrary(migrated)
            return migrated
        }
        return GitMageLibraryState()
    }

    func saveLibrary(_ state: GitMageLibraryState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        documents.setData(data, forKey: libraryKey)
    }

    private func migrateLegacyIfPresent() -> GitMageLibraryState? {
        let legacy = load()
        let path = legacy.repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let repo = GitMageRepoConfig(
            id: UUID().uuidString,
            path: legacy.repositoryPath,
            name: (legacy.repositoryPath as NSString).lastPathComponent,
            draftCommitMessage: legacy.draftCommitMessage
        )
        return GitMageLibraryState(repos: [repo], activeRepoID: repo.id)
    }

    // MARK: - Legacy (v1) — retained for migration and existing tests

    func load() -> GitMageWorkspaceState {
        guard let data = documents.data(forKey: legacyKey) else { return GitMageWorkspaceState() }
        return (try? JSONDecoder().decode(GitMageWorkspaceState.self, from: data)) ?? GitMageWorkspaceState()
    }

    func save(_ state: GitMageWorkspaceState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        documents.setData(data, forKey: legacyKey)
    }
}
