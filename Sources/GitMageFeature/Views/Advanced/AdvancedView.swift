import SwiftUI
import AinkradAppKit

/// Context pane (left rail) for the Advanced Ops area: in-progress banner + op picker.
struct AdvancedContextPane: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.operationState.isActive {
                inProgressBanner
            }
            if let errorMessage = model.errorMessage {
                errorBanner(errorMessage)
            }
            opList
        }
    }

    private var header: some View {
        PaneHeader(title: "ADVANCED", count: AdvancedViewModel.AdvancedOp.allCases.count, tokens: tokens) {
            if model.isLoading { GMSpinner(tint: tokens.accentSecondary, size: 16) }
        }
    }

    private var inProgressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(tokens.accentTertiary)
                Text(model.operationState.label)
                    .font(AinkradFont.display(12, weight: .semibold))
            }
            Text("Resolve conflicts in Changes, then Continue.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
            HStack(spacing: 8) {
                GMButton("Continue", kind: .primary, tokens: tokens) { Task { await model.continueOperation() } }
                    .disabled(model.isLoading)
                GMButton("Abort", kind: .destructive, tokens: tokens) { Task { await model.abortOperation() } }
                    .disabled(model.isLoading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.accentTertiary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.accentTertiary.opacity(0.35))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func errorBanner(_ text: String) -> some View {
        ErrorBanner(message: text, tokens: tokens)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var opList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(AdvancedViewModel.AdvancedOp.allCases) { op in
                    AdvancedOpRow(op: op, tokens: tokens, isSelected: model.selectedOp == op) {
                        model.selectedOp = op
                    }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
    }
}

private struct AdvancedOpRow: View {
    let op: AdvancedViewModel.AdvancedOp
    let tokens: HostThemeTokens
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var icon: String {
        switch op {
        case .rebase: return "arrow.triangle.merge"
        case .cherryPick: return "arrow.right.circle"
        case .revert: return "arrow.uturn.backward"
        case .reset: return "arrow.counterclockwise"
        case .tags: return "tag"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.foreground.opacity(0.55))
                .frame(width: 16)
            Text(op.title)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.88))
            Spacer()
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.13)
                      : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            Capsule().fill(tokens.accentPrimary).frame(width: 3, height: 18)
                .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4).padding(.leading, 1)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}
