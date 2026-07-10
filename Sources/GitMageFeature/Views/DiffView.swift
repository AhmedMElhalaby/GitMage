import SwiftUI
import AinkradAppKit

/// Minimal stub — fleshed out in Task 6.
struct DiffView: View {
    let diff: GitDiffSnapshot?
    let tokens: HostThemeTokens
    let fontSize: Double

    var body: some View {
        Text(diff?.title ?? "—")
    }
}
