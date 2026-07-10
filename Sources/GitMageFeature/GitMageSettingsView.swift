import SwiftUI
import AinkradAppKit

struct GitMageSettingsView: View {
    let host: HostServices

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Git Mage")
                .font(.title2.weight(.semibold))
            Text("Workspace state is stored in the app-scoped document store under a single versioned key.")
                .foregroundStyle(host.theme.tokens.foreground.opacity(0.72))

            VStack(alignment: .leading, spacing: 8) {
                Text("Storage key")
                    .font(.headline)
                Text("workspace.state.v1")
                    .font(.system(.body, design: .monospaced))
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(host.theme.tokens.background)
        .foregroundStyle(host.theme.tokens.foreground)
    }
}

