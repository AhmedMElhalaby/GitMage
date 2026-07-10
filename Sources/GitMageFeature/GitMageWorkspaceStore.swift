import Foundation
import AinkradAppKit

struct GitMageWorkspaceStore {
    private let documents: PluginDocumentStore
    private let key = "workspace.state.v1"

    init(documents: PluginDocumentStore) {
        self.documents = documents
    }

    func load() -> GitMageWorkspaceState {
        guard let data = documents.data(forKey: key) else { return GitMageWorkspaceState() }
        return (try? JSONDecoder().decode(GitMageWorkspaceState.self, from: data)) ?? GitMageWorkspaceState()
    }

    func save(_ state: GitMageWorkspaceState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        documents.setData(data, forKey: key)
    }
}

