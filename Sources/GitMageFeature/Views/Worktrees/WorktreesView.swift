import SwiftUI
import AinkradAppKit

/// Context pane (left rail) for the Worktrees area: header actions + worktree list.
struct WorktreesContextPane: View {
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Worktrees")
                .font(AinkradFont.display(13, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            headerButton("Add…", systemImage: "plus") { model.showAdd = true }
            headerButton("Prune", systemImage: "sparkles") { Task { await model.prune() } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AinkradFont.display(11, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            emptyState(text: errorMessage)
        } else if model.worktrees.isEmpty {
            emptyState(text: "No worktrees.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.worktrees) { wt in
                        WorktreeRow(
                            worktree: wt,
                            tokens: tokens,
                            isSelected: model.selectedPath == wt.path,
                            isCurrent: model.isCurrent(wt),
                            onSelect: { model.select(wt.path) },
                            onOpen: { model.open(wt) },
                            onToggleLock: {
                                Task {
                                    if wt.isLocked {
                                        await model.unlock(wt)
                                    } else {
                                        await model.lock(wt)
                                    }
                                }
                            },
                            onRemove: { Task { await model.remove(wt, force: false) } }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.5))
            Text(text)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let tokens: HostThemeTokens
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onToggleLock: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private var lastPathComponent: String {
        (worktree.path as NSString).lastPathComponent
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                topLine
                Text(worktree.path)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .lineLimit(1)
                bottomLine
                if hovering {
                    actionsRow
                }
            }
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

    private var topLine: some View {
        HStack(spacing: 6) {
            Text(lastPathComponent)
                .font(AinkradFont.display(12, weight: .bold))
                .lineLimit(1)
            if isCurrent {
                Text("current")
                    .font(AinkradFont.display(9, weight: .semibold))
                    .foregroundStyle(tokens.accentPrimary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(tokens.accentPrimary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Spacer()
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            if worktree.isPrunable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
    }

    private var bottomLine: some View {
        Text(worktree.branch ?? "detached")
            .font(AinkradFont.display(10, weight: .medium))
            .foregroundStyle(worktree.branch != nil ? tokens.accentPrimary.opacity(0.85) : tokens.foreground.opacity(0.5))
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            rowAction("Open", systemImage: "arrow.up.forward.square", action: onOpen)
            rowAction(worktree.isLocked ? "Unlock" : "Lock", systemImage: worktree.isLocked ? "lock.open" : "lock", action: onToggleLock)
            rowAction("Remove", systemImage: "trash", action: onRemove)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func rowAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AinkradFont.display(9, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.65))
        }
        .buttonStyle(.plain)
    }
}
