import SwiftUI
import AinkradAppKit

/// Minimal stub — fleshed out in Task 5.
struct ChangesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let accent: Color

    var body: some View {
        Text("Changes")
    }
}
