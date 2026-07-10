import SwiftUI
import AinkradAppKit

struct RepoSwitcher: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    var body: some View {
        Menu {
            ForEach(model.repos) { repo in
                Button {
                    model.selectRepository(repo.id)
                } label: {
                    Label(repo.name, systemImage: repo.id == model.activeRepoID ? "checkmark" : "folder")
                }
            }
            if !model.repos.isEmpty { Divider() }   // Menu items only; not a surface separator
            Button("Add Repository…") { model.addRepositoryFolder() }
            Button("Clone…") { model.startClone() }
            if model.hasActiveRepo {
                Button("Remove Current", role: .destructive) { model.removeActiveRepository() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.gearshape")
                Text(model.activeRepo?.name ?? "No Repository")
                    .font(AinkradFont.display(13, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .foregroundStyle(tokens.foreground.opacity(0.9))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
