import SwiftUI
import AinkradAppKit

struct ChangesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let accent: Color

    private var staged: [GitChange] { model.snapshot?.changes.filter { $0.hasStagedComponent } ?? [] }
    private var unstaged: [GitChange] { model.snapshot?.changes.filter { $0.hasUnstagedComponent } ?? [] }

    /// Group-scoped selection key ("staged:<id>" / "unstaged:<id>") so a file that
    /// appears in both groups only highlights the side the user actually clicked.
    /// The VM's `selectedChangeID` (plain change id) still drives which change the
    /// stage/unstage/discard actions target and is left untouched.
    @State private var selectedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group(title: "STAGED", count: staged.count, changes: staged, staged: true)
                    group(title: "UNSTAGED", count: unstaged.count, changes: unstaged, staged: false)
                }
                .padding(12)
            }
            CommitBox(model: model, tokens: tokens, accent: accent, stagedCount: staged.count)
        }
    }

    @ViewBuilder private func group(title: String, count: Int, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(AinkradFont.display(10, weight: .semibold)).kerning(2).foregroundStyle(tokens.foreground.opacity(0.5))
                    Spacer()
                    Text("\(count)").font(AinkradFont.mono(10)).foregroundStyle(tokens.foreground.opacity(0.5))
                }
                ForEach(changes, id: \.id) { change in
                    let rowID = "\(staged ? "staged" : "unstaged"):\(change.id)"
                    ChangeRow(change: change, isSelected: selectedRowID == rowID, staged: staged, tokens: tokens, accent: accent,
                              onSelect: { selectedRowID = rowID; model.selectChange(change) },
                              onStage: { selectedRowID = rowID; model.selectChange(change); model.stageSelectedChange() },
                              onUnstage: { selectedRowID = rowID; model.selectChange(change); model.unstageSelectedChange() },
                              onDiscard: { selectedRowID = rowID; model.selectChange(change); model.discardSelectedChange() })
                }
            }
        }
    }
}

struct ChangeRow: View {
    let change: GitChange
    let isSelected: Bool
    let staged: Bool
    let tokens: HostThemeTokens
    let accent: Color
    let onSelect: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(change.statusCode.trimmingCharacters(in: .whitespaces).isEmpty ? "•" : change.statusCode)
                    .font(AinkradFont.mono(10)).foregroundStyle(accent)
                    .frame(width: 22)
                Text((change.path as NSString).lastPathComponent)
                    .font(AinkradFont.display(12)).lineLimit(1)
                Spacer()
                if hovering {
                    if staged {
                        rowButton("minus.circle", action: onUnstage)
                    } else {
                        rowButton("plus.circle", action: onStage)
                        rowButton("arrow.uturn.backward.circle", action: onDiscard)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isSelected ? accent.opacity(0.13) : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private func rowButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)) }
            .buttonStyle(.plain).foregroundStyle(tokens.foreground.opacity(0.7))
    }
}

struct CommitBox: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let accent: Color
    let stagedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.draftCommitMessage)
                .font(AinkradFont.display(12))
                .scrollContentBackground(.hidden)
                .frame(height: 72)
                .padding(6)
                .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.2)))
            HStack {
                Text("\(stagedCount) staged").font(AinkradFont.mono(10)).foregroundStyle(tokens.foreground.opacity(0.5))
                Spacer()
                Button { model.commitChanges() } label: {
                    Text("Commit").font(AinkradFont.display(12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(accent.opacity(stagedCount == 0 ? 0.3 : 0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading || stagedCount == 0 || model.draftCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(tokens.surface.opacity(0.5))
    }
}
