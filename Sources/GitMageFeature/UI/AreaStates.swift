import SwiftUI
import AinkradAppKit

/// Centered placeholder shown when a list/pane has no content — e.g. no
/// worktrees, no open PRs. Shared across areas to keep empty-state chrome
/// consistent.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.7))
            Text(title)
                .font(AinkradFont.display(13, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Text(message)
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A tokened inline banner for surfacing an error/warning message without a
/// hard divider line.
struct ErrorBanner: View {
    let message: String
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.accentTertiary)
            Text(message)
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tokens.accentTertiary.opacity(0.12))
        )
    }
}

/// A lightweight loading placeholder row (spinner + label) for in-progress
/// list states.
struct LoadingRow: View {
    let text: String
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
