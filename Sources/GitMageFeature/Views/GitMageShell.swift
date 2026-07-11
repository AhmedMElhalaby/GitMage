import SwiftUI
import AinkradAppKit

struct GitMageShell: View {
    let host: HostServices
    let settingsStore: GitMageSettingsStore
    @StateObject private var model: GitMageViewModel
    @State private var prModel: PullRequestsViewModel?
    @State private var prHasGitHubRemote = false
    @State private var issuesModel: IssuesViewModel?
    @State private var issuesHasGitHubRemote = false
    @State private var worktreesModel: WorktreesViewModel?
    @State private var advancedModel: AdvancedViewModel?
    @State private var management: GitMageManagementKind?

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
        ZStack {
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

            if let management {
                GitMageManagementOverlay(
                    model: model,
                    tokens: tokens,
                    kind: management,
                    dismiss: { withAnimation(.easeOut(duration: 0.16)) { self.management = nil } }
                )
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: management)
        .background(tokens.surface.opacity(appearance.backgroundOpacity))
        .foregroundStyle(tokens.foreground)
        .task { model.bootstrapIfNeeded() }
        .task(id: PRTaskKey(area: model.selectedArea, repoID: model.activeRepoID)) {
            await buildPRModelIfNeeded()
        }
        .task(id: IssuesTaskKey(area: model.selectedArea, repoID: model.activeRepoID)) {
            await buildIssuesModelIfNeeded()
        }
        .task(id: WorktreesTaskKey(isActive: model.selectedArea == .worktrees, repoID: model.activeRepoID)) {
            await buildWorktreesModelIfNeeded()
        }
        .task(id: AdvancedTaskKey(isActive: model.selectedArea == .advanced, repoID: model.activeRepoID)) {
            await buildAdvancedModelIfNeeded()
        }
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
            RepoSwitcher(model: model, tokens: tokens) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { management = .repos }
            }
            if model.hasActiveRepo {
                BranchChip(model: model, tokens: tokens) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { management = .branches }
                }
            }
            Spacer()
            if model.hasActiveRepo {
                TopBarActionButton(label: "Fetch", icon: "arrow.down.circle",
                                   isLoading: model.activeOperation == "fetch", tokens: tokens) { model.fetch() }
                TopBarActionButton(label: "Pull", icon: "arrow.down.to.line",
                                   isLoading: model.activeOperation == "pull", tokens: tokens) { model.pull() }
                TopBarActionButton(label: "Push", icon: "arrow.up.to.line", isPrimary: true,
                                   isLoading: model.activeOperation == "push", tokens: tokens) { model.push() }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var navRail: some View {
        VStack(spacing: 10) {
            ForEach(NavArea.built) { area in navItem(area) }
            Spacer()
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
                .foregroundStyle(isActive ? tokens.accentPrimary : tokens.foreground.opacity(0.7))
                .frame(width: 40, height: 34)
                .background(isActive ? tokens.accentPrimary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(area.title)
        .animation(.easeOut(duration: 0.14), value: isActive)
    }

    @ViewBuilder private var contextPane: some View {
        switch model.selectedArea {
        case .changes: ChangesContextPane(model: model, tokens: tokens, accent: appearance.accent)
        case .history: HistoryContextPane(model: model, tokens: tokens)
        case .branches: BranchesContextPane(model: model, tokens: tokens)
        case .stashes: StashesContextPane(model: model, tokens: tokens)
        case .pullRequests:
            if let prModel {
                PullRequestsContextPane(model: prModel, tokens: tokens, hasGitHubRemote: prHasGitHubRemote)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .issues:
            if let issuesModel {
                IssuesContextPane(model: issuesModel, tokens: tokens, hasGitHubRemote: issuesHasGitHubRemote)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .worktrees:
            if let worktreesModel {
                WorktreesContextPane(model: worktreesModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        case .advanced:
            if let advancedModel {
                AdvancedContextPane(model: advancedModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        default: EmptyView()
        }
    }

    @ViewBuilder private var detailPane: some View {
        switch model.selectedArea {
        case .changes: DiffView(diff: model.diffSnapshot, tokens: tokens, fontSize: appearance.diffFontSize)
        case .history: DiffView(diff: model.commitDiff, tokens: tokens, fontSize: appearance.diffFontSize)
        case .branches:
            EmptyStateView(
                icon: "arrow.triangle.branch",
                title: model.selectedBranchName.isEmpty ? "Branches" : model.selectedBranchName,
                message: "Select a branch to check out from the list.",
                tokens: tokens
            )
        case .stashes:
            if let selectedStashDiff = model.selectedStashDiff {
                DiffView(diff: selectedStashDiff, tokens: tokens, fontSize: appearance.diffFontSize)
            } else {
                EmptyStateView(
                    icon: "tray.2",
                    title: "Stashes",
                    message: "Select a stash to preview its diff.",
                    tokens: tokens
                )
            }
        case .pullRequests:
            if let prModel {
                PullRequestDetailView(model: prModel, tokens: tokens, fontSize: appearance.diffFontSize)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .issues:
            if let issuesModel {
                IssueDetailView(model: issuesModel, tokens: tokens)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .worktrees:
            if let worktreesModel {
                WorktreeDetailView(model: worktreesModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        case .advanced:
            if let advancedModel {
                AdvancedDetailView(model: advancedModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        default: ComingSoonView(area: model.selectedArea, tokens: tokens)
        }
    }

    private var selectRepoPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.5))
            Text("Select a repository.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct PRTaskKey: Equatable {
        let area: NavArea
        let repoID: String?
    }

    private struct IssuesTaskKey: Equatable {
        let area: NavArea
        let repoID: String?
    }

    private struct WorktreesTaskKey: Equatable {
        let isActive: Bool
        let repoID: String?
    }

    private struct AdvancedTaskKey: Equatable {
        let isActive: Bool
        let repoID: String?
    }

    private func buildPRModelIfNeeded() async {
        guard model.selectedArea == .pullRequests else { return }
        let remote = await model.currentRemote()
        prHasGitHubRemote = remote?.host.lowercased().contains("github.com") == true
        let auth = GitForgeAuth(secrets: host.secrets)
        let token = auth.token()
        let provider: GitForgeProvider? = token.map { GitHubProvider(token: $0) }
        let newModel = PullRequestsViewModel(repo: remote, provider: provider, auth: auth)
        prModel = newModel
        await newModel.verify()
        if remote != nil && token != nil {
            await newModel.load()
        }
    }

    private func buildIssuesModelIfNeeded() async {
        guard model.selectedArea == .issues else { return }
        let remote = await model.currentRemote()
        issuesHasGitHubRemote = remote?.host.lowercased().contains("github.com") == true
        let auth = GitForgeAuth(secrets: host.secrets)
        let token = auth.token()
        let provider: GitForgeProvider? = token.map { GitHubProvider(token: $0) }
        let newModel = IssuesViewModel(repo: remote, provider: provider, auth: auth)
        issuesModel = newModel
        await newModel.verify()
        if remote != nil && token != nil {
            await newModel.load()
        }
    }

    private func buildWorktreesModelIfNeeded() async {
        guard model.selectedArea == .worktrees, model.hasActiveRepo else { return }
        let newModel = WorktreesViewModel(
            client: GitRepositoryClient(),
            repositoryPath: model.repositoryPath,
            currentRoot: model.snapshot?.rootPath ?? "",
            branches: model.branches,
            onOpen: { path in model.openRepositoryPath(path) }
        )
        worktreesModel = newModel
        await newModel.load()
    }

    private func buildAdvancedModelIfNeeded() async {
        guard model.selectedArea == .advanced, model.hasActiveRepo else { return }
        let newModel = AdvancedViewModel(
            client: GitRepositoryClient(),
            repositoryPath: model.repositoryPath,
            branches: model.branches,
            onChanged: { Task { @MainActor in model.refresh() } }
        )
        advancedModel = newModel
        await newModel.load()
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
