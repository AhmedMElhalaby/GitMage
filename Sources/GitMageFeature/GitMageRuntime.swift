import AinkradAppKit

/// Bridges Git Mage's static `AinkradApp` entry points to one shared, observable
/// `GitMageSettingsStore` per host, keyed by host object identity — so the root
/// view, the settings pane, and `chromeFill` share a single store and restyle live.
@MainActor
enum GitMageRuntime {
    private static var stores: [ObjectIdentifier: GitMageSettingsStore] = [:]

    static func settingsStore(for host: HostServices) -> GitMageSettingsStore {
        let key = ObjectIdentifier(host as AnyObject)
        if let existing = stores[key] { return existing }
        let store = GitMageSettingsStore(documents: host.documents)
        stores[key] = store
        return store
    }
}
