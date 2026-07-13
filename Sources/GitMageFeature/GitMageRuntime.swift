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

    private static var bridges: [ObjectIdentifier: GitMageContextBridge] = [:]

    /// The per-host agent-context bridge. Created and **registered with the host
    /// once** on first request (mirrors `settingsStore` — a Block's shell and
    /// settings share one host, hence one bridge). Never removed: the registered
    /// closure returns nil once the shell's view model is gone or no repo is open.
    static func contextBridge(for host: HostServices) -> GitMageContextBridge {
        let key = ObjectIdentifier(host as AnyObject)
        if let existing = bridges[key] { return existing }
        let bridge = GitMageContextBridge()
        bridges[key] = bridge
        _ = host.context.register { bridge.snapshot() }
        return bridge
    }
}
