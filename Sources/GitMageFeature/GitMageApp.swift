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

