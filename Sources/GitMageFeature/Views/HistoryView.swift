import SwiftUI
import AinkradAppKit

/// Minimal stub — fleshed out in Task 5.
struct HistoryContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        Text("History")
    }
}
