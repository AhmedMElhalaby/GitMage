import SwiftUI
import AinkradAppKit

/// Detail pane for the Advanced area: one page of contextual actions — the
/// selected commit's ops (cherry-pick / revert / reset / tag-target), a rebase
/// card, and a tags card. No per-action page.
struct AdvancedDetailView: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    private var selectedCommit: GitCommitSummary? {
        guard let sha = model.selectedCommit else { return nil }
        return model.commits.first { $0.id == sha }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.operationState.isActive { inProgressBanner }
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage, tokens: tokens)
                }
                AutostashToggle(isOn: $model.autostash, tokens: tokens)
                commitActionsCard
                rebaseCard
                tagsCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if let pending = model.pendingConfirm {
                HUDConfirmDialog(
                    title: pending.title, message: pending.message,
                    isDestructive: true, tokens: tokens,
                    onConfirm: { Task { await model.confirmPending() } },
                    onCancel: { model.cancelPending() }
                )
            }
        }
    }

    // MARK: - In-progress banner

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentTertiary.opacity(0.08)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentTertiary.opacity(0.35)))
    }

    // MARK: - Commit actions

    private var commitActionsCard: some View {
        card("SELECTED COMMIT") {
            if let commit = selectedCommit {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.summary)
                            .font(AinkradFont.display(13, weight: .medium))
                            .foregroundStyle(tokens.foreground)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(commit.shortSHA).font(AinkradFont.mono(10, weight: .medium)).foregroundStyle(tokens.accentSecondary)
                            Text(commit.author).font(AinkradFont.display(10)).foregroundStyle(tokens.foreground.opacity(0.5))
                            Text(commit.relativeDate).font(AinkradFont.display(10)).foregroundStyle(tokens.foreground.opacity(0.4))
                        }
                    }

                    HStack(spacing: 8) {
                        GMButton("Cherry-pick", kind: .secondary, systemImage: "arrow.right.circle", tokens: tokens) {
                            Task { await model.cherryPick() }
                        }.disabled(model.isLoading)
                        GMButton("Revert", kind: .secondary, systemImage: "arrow.uturn.backward", tokens: tokens) {
                            Task { await model.revert() }
                        }.disabled(model.isLoading)
                        Spacer()
                    }

                    // Reset row
                    HStack(spacing: 8) {
                        HUDFilter(
                            options: ResetMode.allCases.map { ($0.rawValue.capitalized, $0) },
                            selection: $model.resetMode, tokens: tokens
                        )
                        .frame(maxWidth: 240)
                        GMButton("Reset to here", kind: .destructive, systemImage: "arrow.counterclockwise", tokens: tokens) {
                            model.requestReset()
                        }.disabled(model.isLoading)
                        Spacer()
                    }
                }
            } else {
                Text("Select a commit from the list to cherry-pick, revert, reset, or tag it.")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
    }

    // MARK: - Rebase

    private var rebaseCard: some View {
        card("REBASE") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Rebase \(model.currentBranchName) onto")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    HUDMenu(
                        tokens: tokens,
                        items: model.branchNames.map { HUDMenuItem(id: $0, title: $0, isSelected: $0 == model.rebaseBase) },
                        onPick: { model.rebaseBase = $0 }
                    ) {
                        HUDMenuLabel(text: model.rebaseBase ?? "Choose a branch",
                                     isPlaceholder: model.rebaseBase == nil, tokens: tokens)
                            .frame(width: 180)
                    }
                }
                GMButton("Rebase", kind: .primary, systemImage: "arrow.triangle.merge", tokens: tokens) {
                    model.requestRebase()
                }
                .disabled(model.isLoading || model.rebaseBase == nil || model.rebaseBase?.isEmpty == true)
            }
        }
    }

    // MARK: - Tags

    private var tagTarget: String {
        if let commit = selectedCommit { return commit.shortSHA }
        return "HEAD (\(model.currentBranchName))"
    }

    private var tagsCard: some View {
        card("TAGS") {
            VStack(alignment: .leading, spacing: 10) {
                if model.tags.isEmpty {
                    Text("No tags yet.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(model.tags) { tag in
                                TagRow(tag: tag, tokens: tokens) { Task { await model.deleteTag(tag.name) } }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Text("NEW TAG AT \(tagTarget)")
                    .font(AinkradFont.display(9, weight: .semibold)).kerning(1)
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                AinkradTextField(text: $model.newTagName, placeholder: "Tag name")
                AinkradTextField(text: $model.newTagMessage, placeholder: "Message (optional)")
                GMButton("Create tag", kind: .primary, systemImage: "tag", tokens: tokens) {
                    Task { await model.createTag() }
                }
                .disabled(model.isLoading || model.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Card chrome

    @ViewBuilder private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AinkradFont.display(10, weight: .semibold)).kerning(2)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.25)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.foreground.opacity(0.07)))
    }
}

/// Labeled HUD toggle row for the auto-stash option.
private struct AutostashToggle: View {
    @Binding var isOn: Bool
    let tokens: HostThemeTokens

    var body: some View {
        HStack {
            Text("Auto-stash uncommitted changes before rebase/reset")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            NeonToggle(isOn: $isOn, tokens: tokens)
        }
    }
}

private struct TagRow: View {
    let tag: GitTag
    let tokens: HostThemeTokens
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag").font(.system(size: 10)).foregroundStyle(tokens.accentSecondary.opacity(0.8)).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name).font(AinkradFont.display(12, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.9))
                if let message = tag.message, !message.isEmpty {
                    Text(message)
                        .font(AinkradFont.display(10))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
            RowIconButton(symbol: "trash", help: "Delete tag", tokens: tokens, size: 20, action: onDelete)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear, in: ChamferShape(cut: AinkradRadius.md))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
