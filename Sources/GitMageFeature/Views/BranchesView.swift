import SwiftUI
import AinkradAppKit

struct BranchesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("new-branch", text: $newName).textFieldStyle(.plain)
                    .font(AinkradFont.display(12))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button { model.newBranchName = newName; model.createBranch(); newName = "" } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.branches) { branch in
                        BranchRow(branch: branch, tokens: tokens,
                                  onCheckout: { model.selectedBranchName = branch.name; model.checkoutSelectedBranch() },
                                  onDelete: { model.deleteBranch(branch.name) })
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

private struct BranchRow: View {
    let branch: GitBranchSummary
    let tokens: HostThemeTokens
    let onCheckout: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(branch.isCurrent ? tokens.accentPrimary : tokens.foreground.opacity(0.4))
            VStack(alignment: .leading, spacing: 1) {
                Text(branch.name).font(AinkradFont.display(12))
                Text(branch.subtitle).font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer()
            if hovering && !branch.isCurrent {
                Button(action: onCheckout) { Image(systemName: "arrow.right.circle") }.buttonStyle(.plain)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(tokens.foreground.opacity(0.7))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onCheckout)
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
