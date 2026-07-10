import SwiftUI
import AinkradAppKit

/// Minimal stub — fleshed out in Task 6.
struct StashesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        Text("Stashes")
    }
}
