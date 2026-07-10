import SwiftUI
import AinkradAppKit

struct GitMageSettingsView: View {
    let settingsStore: GitMageSettingsStore
    let theme: HostTheme

    private var tokens: HostThemeTokens { theme.tokens }
    private var settings: GitMageSettings { settingsStore.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                appearanceSection
                aboutSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background)
        .foregroundStyle(tokens.foreground)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Background opacity")
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                Slider(
                    value: Binding(
                        get: { settings.backgroundOpacity },
                        set: { v in settingsStore.update { $0.backgroundOpacity = v } }
                    ),
                    in: 0.2...1.0
                )
                .tint(tokens.accentPrimary)
                Text("Below 100%, the workspace backdrop shows through. Blur is managed by the host.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }

            HStack {
                Text("Follow theme accent")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
                NeonToggle(
                    isOn: Binding(
                        get: { settings.followThemeAccent },
                        set: { v in settingsStore.update { $0.followThemeAccent = v } }
                    ),
                    tokens: tokens
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Diff text size")
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    Text("\(Int(settings.diffFontSize)) pt")
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                Slider(
                    value: Binding(
                        get: { settings.diffFontSize },
                        set: { v in settingsStore.update { $0.diffFontSize = v.rounded() } }
                    ),
                    in: 9...20
                )
                .tint(tokens.accentPrimary)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "STORAGE", tokens: tokens)
            Text("Your repository library and settings are stored in Git Mage's app-scoped document store.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
    }
}
