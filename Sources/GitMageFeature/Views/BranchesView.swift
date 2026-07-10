import SwiftUI
import AinkradAppKit

/// Minimal stub — fleshed out in Task 6.
struct BranchesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        Text("Branches")
    }
}
