import Foundation
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

    private static var actionTokens: [ObjectIdentifier: AgentActionToken] = [:]
    private static let sharedClient = GitRepositoryClient()

    /// Register the host's `gitmage.git_op` handler **once**. Reuses one
    /// `GitRepositoryClient` (path-scoped per call). Never torn down.
    static func registerActions(for host: HostServices) {
        let key = ObjectIdentifier(host as AnyObject)
        guard actionTokens[key] == nil else { return }
        let handler = GitOpActionHandler(client: sharedClient)
        let token = host.actions.register(actionID: "gitmage.git_op") { json in
            await handler.run(json)
        }
        actionTokens[key] = token
    }
}
