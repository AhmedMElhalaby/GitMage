import Foundation

/// Git Mage's per-app settings, persisted through the app-scoped document store.
/// Decoding tolerates payloads written before a field existed.
struct GitMageSettings: Codable, Equatable {
    static let documentID = "gitmage-settings"

    /// Surface alpha (0.2…1.0). < 1 reveals the host's shared blurred backdrop.
    var backgroundOpacity: Double = 1.0
    /// When true, accents follow the theme's primary accent; when false, the
    /// theme's secondary accent is used for visual differentiation.
    var followThemeAccent: Bool = true
    /// Point size of the monospaced diff text.
    var diffFontSize: Double = 12
    /// Command → key chord bindings, keyed by `GitMageCommand.rawValue`. A
    /// missing command is intentionally unbound.
    var shortcuts: [String: KeyChord] = GitMageShortcutDefaults.map

    init(backgroundOpacity: Double = 1.0, followThemeAccent: Bool = true,
         diffFontSize: Double = 12, shortcuts: [String: KeyChord] = GitMageShortcutDefaults.map) {
        self.backgroundOpacity = backgroundOpacity
        self.followThemeAccent = followThemeAccent
        self.diffFontSize = diffFontSize
        self.shortcuts = shortcuts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1.0
        followThemeAccent = try c.decodeIfPresent(Bool.self, forKey: .followThemeAccent) ?? true
        diffFontSize = try c.decodeIfPresent(Double.self, forKey: .diffFontSize) ?? 12
        shortcuts = try c.decodeIfPresent([String: KeyChord].self, forKey: .shortcuts) ?? GitMageShortcutDefaults.map
    }
}
