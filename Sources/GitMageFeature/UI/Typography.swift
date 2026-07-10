import SwiftUI

/// The two brand typefaces — see 06 Brand/Brand Identity.md. Exo 2 for
/// display/UI text, JetBrains Mono for data and HUD readouts. These fonts are
/// registered process-wide by the host; this app resolves them by name. Falls
/// back to the system face automatically if a face isn't registered.
enum AinkradFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Exo 2", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}
