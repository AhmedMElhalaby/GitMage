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
        applyTypography()
    }

    func update(_ mutate: (inout GitMageSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
        applyTypography()
        if let data = try? JSONEncoder().encode(updated) {
            documents.setData(data, forKey: Self.key)
        }
    }

    /// Pushes the current typography settings into `AinkradFont` so every
    /// `display`/`mono` call across the UI reflects them.
    private func applyTypography() {
        AinkradFont.config = AinkradFont.Config(
            scale: CGFloat(settings.textScale),
            displayFamily: settings.displayFontName,
            monoFamily: settings.monoFontName
        )
    }
}
