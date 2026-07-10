import SwiftUI
import AinkradAppKit

public struct GitMageApp: AinkradApp {
    public static let id = "gitmage"
    public static let displayName = "Git Mage"
    public static let icon = "wand.and.stars"

    public static func makeRootView(host: HostServices) -> AnyView {
        AnyView(GitMageRootView(host: host))
    }

    public static func makeSettingsView(host: HostServices) -> AnyView {
        AnyView(GitMageSettingsView(host: host))
    }
}

