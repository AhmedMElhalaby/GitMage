import SwiftUI
import AinkradAppKit

struct GitMageShell: View {
    let host: HostServices
    let settingsStore: GitMageSettingsStore
    @StateObject private var model: GitMageViewModel

    init(host: HostServices, settingsStore: GitMageSettingsStore) {
        self.host = host
        self.settingsStore = settingsStore
        _model = StateObject(wrappedValue: GitMageViewModel(host: host))
    }

    private var tokens: HostThemeTokens { host.theme.tokens }
    private var appearance: GitMageRenderAppearance {
        GitMageAppearanceResolver.resolve(settings: settingsStore.settings, tokens: tokens)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                navRail
                if model.hasActiveRepo {
                    contextPane
                        .frame(width: 300)
                        .background(tokens.surface.opacity(0.35))
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyLibraryState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(tokens.surface.opacity(appearance.backgroundOpacity))
        .foregroundStyle(tokens.foreground)
        .task { model.bootstrapIfNeeded() }
        .alert("Initialize a new Git repository?", isPresented: $model.showInitPrompt) {
            Button("Cancel", role: .cancel) { model.cancelInitPendingRepository() }
            Button("Initialize") { model.confirmInitPendingRepository() }
        } message: {
            Text("\(model.pendingInitPath ?? "") is not a Git repository yet. Initialize it and add it to your library?")
        }
        .sheet(isPresented: $model.showClonePrompt) { cloneSheet }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            RepoSwitcher(model: model, tokens: tokens)
            if model.hasActiveRepo {
                branchMenu
            }
            Spacer()
            if model.hasActiveRepo {
                remoteButton("Fetch", systemImage: "arrow.down.circle") { model.fetch() }
                remoteButton("Pull", systemImage: "arrow.down.to.line") { model.pull() }
                remoteButton("Push", systemImage: "arrow.up.to.line") { model.push() }
            }
            if model.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var branchMenu: some View {
        Menu {
            ForEach(model.branches) { branch in
                Button {
                    model.selectedBranchName = branch.name
                    model.checkoutSelectedBranch()
                } label: {
                    Label(branch.name, systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(model.snapshot?.branchName ?? "—").font(AinkradFont.display(12))
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .foregroundStyle(tokens.foreground.opacity(0.8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func remoteButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(AinkradFont.display(12, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tokens.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.2)))
    }

    private var navRail: some View {
        VStack(spacing: 10) {
            ForEach(NavArea.built) { area in navItem(area) }
            Spacer()
            ForEach(NavArea.reserved) { area in navItem(area) }
        }
        .padding(.vertical, 14)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(tokens.background.opacity(0.4))
    }

    private func navItem(_ area: NavArea) -> some View {
        let isActive = model.selectedArea == area
        return Button { model.selectArea(area) } label: {
            Image(systemName: area.icon)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? tokens.accentPrimary : tokens.foreground.opacity(area.isReserved ? 0.35 : 0.7))
                .frame(width: 40, height: 34)
                .background(isActive ? tokens.accentPrimary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(area.title + (area.isReserved ? " (coming soon)" : ""))
        .animation(.easeOut(duration: 0.14), value: isActive)
    }

    @ViewBuilder private var contextPane: some View {
        switch model.selectedArea {
        case .changes: ChangesContextPane(model: model, tokens: tokens, accent: appearance.accent)
        case .history: HistoryContextPane(model: model, tokens: tokens)
        case .branches: BranchesContextPane(model: model, tokens: tokens)
        case .stashes: StashesContextPane(model: model, tokens: tokens)
        default: EmptyView()
        }
    }

    @ViewBuilder private var detailPane: some View {
        switch model.selectedArea {
        case .changes: DiffView(diff: model.diffSnapshot, tokens: tokens, fontSize: appearance.diffFontSize)
        case .history: DiffView(diff: model.commitDiff, tokens: tokens, fontSize: appearance.diffFontSize)
        case .branches, .stashes: DiffView(diff: model.diffSnapshot, tokens: tokens, fontSize: appearance.diffFontSize)
        default: ComingSoonView(area: model.selectedArea, tokens: tokens)
        }
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 34, weight: .light)).foregroundStyle(tokens.accentPrimary.opacity(0.6))
            Text("No repository").font(AinkradFont.display(18, weight: .semibold))
            Text("Add a local folder or clone one to begin.").font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.5))
            HStack {
                Button("Add…") { model.addRepositoryFolder() }
                Button("Clone…") { model.startClone() }
            }
        }
    }

    private var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone a Repository").font(AinkradFont.display(18, weight: .semibold))
            Text("Enter a Git remote URL. You'll then choose a destination folder.")
                .font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.7))
            TextField("https://github.com/owner/repo.git", text: $model.cloneRemoteURL)
                .textFieldStyle(.roundedBorder).frame(minWidth: 380)
            HStack {
                Spacer()
                Button("Cancel") { model.showClonePrompt = false }
                Button("Choose Destination & Clone") { model.performClone() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.cloneRemoteURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(minWidth: 440)
        .background(tokens.background).foregroundStyle(tokens.foreground)
    }
}
