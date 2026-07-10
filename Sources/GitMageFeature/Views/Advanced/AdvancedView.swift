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
        HStack(spacing: 8) {
            Text("Advanced")
                .font(AinkradFont.display(13, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                Button("Continue") { Task { await model.continueOperation() } }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tokens.accentPrimary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Button("Abort") { Task { await model.abortOperation() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(tokens.accentTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tokens.accentTertiary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(12)
        .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(11))
            .foregroundStyle(tokens.accentTertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var opList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AdvancedViewModel.AdvancedOp.allCases) { op in
                    opRow(op)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func opRow(_ op: AdvancedViewModel.AdvancedOp) -> some View {
        AdvancedOpRow(op: op, tokens: tokens, isSelected: model.selectedOp == op) {
            model.selectedOp = op
        }
    }
}

private struct AdvancedOpRow: View {
    let op: AdvancedViewModel.AdvancedOp
    let tokens: HostThemeTokens
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(op.title)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(
                    isSelected ? tokens.accentPrimary.opacity(0.13) : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
