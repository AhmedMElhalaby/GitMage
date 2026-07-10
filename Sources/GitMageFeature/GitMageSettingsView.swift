import SwiftUI
import AinkradAppKit

struct GitMageSettingsView: View {
    let settingsStore: GitMageSettingsStore
    let theme: HostTheme
    let host: HostServices

    @State private var tokenDraft: String = ""
    @State private var githubStatus: String?
    @State private var isVerifying: Bool = false

    private var tokens: HostThemeTokens { theme.tokens }
    private var settings: GitMageSettings { settingsStore.settings }
    private var auth: GitForgeAuth { GitForgeAuth(secrets: host.secrets) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                appearanceSection
                githubSection
                aboutSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background)
        .foregroundStyle(tokens.foreground)
        .onAppear {
            if auth.token() != nil {
                githubStatus = "A token is saved."
            }
        }
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

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "GITHUB", tokens: tokens)

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal access token")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))

                SecureField("Personal access token", text: $tokenDraft)
                    .textFieldStyle(.plain)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tokens.accentPrimary.opacity(0.2))
                    )

                HStack(spacing: 10) {
                    Button {
                        saveAndVerify()
                    } label: {
                        HStack(spacing: 6) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Save & Verify")
                        }
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tokens.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(tokens.accentPrimary.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(tokenDraft.isEmpty || isVerifying)

                    if auth.token() != nil {
                        Button {
                            signOut()
                        } label: {
                            Text("Sign out")
                                .font(AinkradFont.display(12, weight: .medium))
                                .foregroundStyle(tokens.foreground.opacity(0.85))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(tokens.surfaceElevated.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(tokens.accentPrimary.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let githubStatus {
                    Text(githubStatus)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }

                Text("Create a token with the `repo` scope at github.com → Settings → Developer settings → Personal access tokens.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
        }
    }

    private func saveAndVerify() {
        auth.setToken(tokenDraft)
        let token = tokenDraft
        isVerifying = true
        githubStatus = nil
        Task { @MainActor in
            defer { isVerifying = false }
            do {
                let provider = GitHubProvider(token: token)
                let user = try await provider.verify()
                githubStatus = "Signed in as \(user.login)."
            } catch let error as ForgeError {
                githubStatus = error.errorDescription
            } catch {
                githubStatus = error.localizedDescription
            }
        }
    }

    private func signOut() {
        auth.clear()
        tokenDraft = ""
        githubStatus = nil
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
