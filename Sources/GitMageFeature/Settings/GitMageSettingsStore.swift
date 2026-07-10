import Observation
import Foundation
import AinkradAppKit

/// Observable owner of `GitMageSettings`, backed by app-scoped `documents`.
/// Editing persists immediately and publishes to observers so the settings UI,
/// every view, and `chromeFill` restyle live.
@MainActor
@Observable
final class GitMageSettingsStore {
    private(set) var settings: GitMageSettings
    private let documents: PluginDocumentStore
    private static let key = GitMageSettings.documentID

    init(documents: PluginDocumentStore) {
        self.documents = documents
        if let data = documents.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(GitMageSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = GitMageSettings()
        }
    }

    func update(_ mutate: (inout GitMageSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
        if let data = try? JSONEncoder().encode(updated) {
            documents.setData(data, forKey: Self.key)
        }
    }
}
