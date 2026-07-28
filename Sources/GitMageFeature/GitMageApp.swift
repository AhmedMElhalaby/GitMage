import SwiftUI
import AinkradAppKit

public struct GitMageApp: AinkradApp {
    public static let id = "gitmage"
    public static let displayName = "Git Mage"
    public static let icon = "wand.and.stars"

    public static func makeRootView(host: HostServices) -> AnyView {
        AnyView(GitMageShell(host: host, settingsStore: GitMageRuntime.settingsStore(for: host)))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(GitMageSettingsView(
            settingsStore: GitMageRuntime.settingsStore(for: host),
            theme: host.theme,
            host: host
        ))
    }

    /// The window surface: the theme surface at the configured opacity so the
    /// title bar reads continuous with the body, and the host reveals its shared
    /// blurred backdrop when opacity < 1.
    public static func chromeFill(host: HostServices) -> Color? {
        let appearance = GitMageAppearanceResolver.resolve(
            settings: GitMageRuntime.settingsStore(for: host).settings,
            tokens: host.theme.tokens
        )
        return host.theme.tokens.surface.opacity(appearance.backgroundOpacity)
    }
}

/// Publishes Git Mage's git operations to the host assistant as MCP tools.
/// Cached per host by the runtime, so the assistant and the UI share one client.
extension GitMageApp: AinkradAppMCP {
    public static func makeMCPServer(host: HostServices) -> MCPAppServer {
        GitMageRuntime.mcpServer(for: host)
    }
}

/// Generation 8: release this instance when the host closes it.
///
/// `GitMageRuntime` held three static, never-evicted registries — settings
/// store, context bridge, and the `gitmage.git_op` action token. Closing Git
/// Mage left all three live for the rest of the process, including a context
/// source the agent kept consulting.
///
/// `host` is nil here because teardown is keyed on identity alone; the runtime
/// keeps the tokens it needs to unregister.
extension GitMageApp: AinkradAppTeardown {
    public static func teardown(instance: PluginInstanceID) {
        GitMageRuntime.teardown(instance: instance, host: nil)
    }
}
