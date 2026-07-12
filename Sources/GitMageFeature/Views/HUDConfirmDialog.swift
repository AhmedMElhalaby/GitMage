import SwiftUI
import AinkradAppKit

/// A HUD replacement for a system `.alert`: a dimmed backdrop and a centered
/// HUD card with title, message, and Cancel / Confirm buttons. Present it from
/// a parent `.overlay` when a bound value is non-nil.
struct HUDConfirmDialog: View {
    let title: String
    let message: String
    var confirmTitle: String = "Confirm"
    var isDestructive: Bool = false
    let tokens: HostThemeTokens
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isDestructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isDestructive ? tokens.accentTertiary : tokens.accentPrimary)
                    Text(title)
                        .font(AinkradFont.display(15, weight: .semibold))
                        .foregroundStyle(tokens.foreground)
                }
                Text(message)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    GMButton("Cancel", kind: .secondary, tokens: tokens, action: onCancel)
                    GMButton(confirmTitle, kind: isDestructive ? .destructive : .primary, tokens: tokens, action: onConfirm)
                }
                .padding(.top, 2)
            }
            .padding(18)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tokens.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [(isDestructive ? tokens.accentTertiary : tokens.accentSecondary).opacity(0.55),
                                     tokens.accentPrimary.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: (isDestructive ? tokens.accentTertiary : tokens.accentPrimary).opacity(0.3), radius: 34, y: 12)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 16)
        }
    }
}
