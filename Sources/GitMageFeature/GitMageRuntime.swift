import Foundation
import AinkradAppKit

/// Bridges Git Mage's static `AinkradApp` entry points to one shared, observable
/// `GitMageSettingsStore` per plugin instance — so the root view, the settings
/// pane, and `chromeFill` share a single store and restyle live.
///
/// Keyed by the HOST-MINTED `PluginInstanceID`. It used to be keyed by
/// `ObjectIdentifier(host as AnyObject)`: the address of a box around a
/// non-class-bound existential, which the runtime is free to reuse once freed.
/// A new host could therefore be handed the previous host's settings store —
/// and nothing was ever evicted, so all three of these dictionaries grew for
/// the life of the process.
@MainActor
enum GitMageRuntime {
    private static let stores = PluginInstanceStorage<GitMageSettingsStore>()

    /// The instance key for `host`.
    ///
    /// A generation-8 host mints one. A generation-7 host does not implement
    /// `PluginInstanceIdentity`, so we fall back to the OLD behaviour —
    /// per-host object identity — rather than to a single shared id. Collapsing
    /// every legacy host onto one key would make two hosts share a settings
    /// store and skip the context registration for the second, which is a
    /// regression, not a fallback. The address-reuse hazard remains only on the
    /// legacy path, exactly as before, and disappears the moment the host is
    /// generation 8.
    static func instance(of host: HostServices) -> PluginInstanceID {
        if let identified = host as? PluginInstanceIdentity { return identified.instanceID }
        let key = ObjectIdentifier(host as AnyObject)
        if let existing = legacyIDs[key] { return existing }
        let minted = PluginInstanceID()
        legacyIDs[key] = minted
        return minted
    }
    private static var legacyIDs: [ObjectIdentifier: PluginInstanceID] = [:]

    static func settingsStore(for host: HostServices) -> GitMageSettingsStore {
        stores.value(for: instance(of: host)) { GitMageSettingsStore(documents: host.documents) }
    }

    private static let bridges = PluginInstanceStorage<GitMageContextBridge>()

    /// The per-host agent-context bridge. Created and **registered with the host
    /// once** on first request (mirrors `settingsStore` — a Block's shell and
    /// settings share one host, hence one bridge). Never removed: the registered
    /// closure returns nil once the shell's view model is gone or no repo is open.
    static func contextBridge(for host: HostServices) -> GitMageContextBridge {
        let id = instance(of: host)
        var created: GitMageContextBridge?
        let bridge = bridges.value(for: id) {
            let made = GitMageContextBridge()
            created = made
            return made
        }
        // Register with the host only on first creation, and keep the token so
        // `teardown` can remove it — previously "never removed", which left a
        // dead context source registered for every instance ever opened.
        if created != nil {
            contextTokens.value(for: id) { host.context.register { bridge.snapshot() } }
        }
        return bridge
    }

    private static let contextTokens = PluginInstanceStorage<PluginContextToken>()
    private static let actionTokens = PluginInstanceStorage<AgentActionToken>()
    private static let sharedClient = GitRepositoryClient()

    /// Register the host's `gitmage.git_op` handler **once**. Reuses one
    /// `GitRepositoryClient` (path-scoped per call). Never torn down.
    static func registerActions(for host: HostServices) {
        let handler = GitOpActionHandler(client: sharedClient)
        _ = actionTokens.value(for: instance(of: host)) {
            host.actions.register(actionID: "gitmage.git_op") { json in
                await handler.run(json)
            }
        }
    }

    /// Releases everything scoped to `instance` and unregisters it from the
    /// host. The three registries above were `static` and never evicted, so a
    /// closed Git Mage left its settings store, its context source and its
    /// `gitmage.git_op` action handler live for the rest of the process.
    static func teardown(instance: PluginInstanceID, host: HostServices?) {
        stores.remove(instance)
        bridges.remove(instance)
        if let token = contextTokens.remove(instance) { host?.context.remove(token) }
        if let token = actionTokens.remove(instance) { host?.actions.remove(token) }
    }
}
