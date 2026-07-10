import Foundation

/// Drives the Pull Requests area of the UI: lists PRs for the active repo,
/// loads a selected PR's detail/files/comments/checks, and performs write
/// actions (comment/review/merge). Gated on having both a recognized repo
/// remote and a configured GitHub token.
@MainActor
final class PullRequestsViewModel: ObservableObject {
    enum AuthState: Equatable {
        case unknown
        case missingToken
        case valid(String)
        case invalid(String)
    }

    @Published var pullRequests: [PullRequestSummary] = []
    @Published var selectedPRNumber: Int?
    @Published var detail: PullRequestDetail?
    @Published var files: [PRFile] = []
    @Published var comments: [PRComment] = []
    @Published var checks: [CheckRun] = []
    @Published var filter: PRState = .open
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authState: AuthState = .unknown

    private let repo: RepoRef?
    private nonisolated(unsafe) let provider: GitForgeProvider?
    private let auth: GitForgeAuth

    init(repo: RepoRef?, provider: GitForgeProvider?, auth: GitForgeAuth) {
        self.repo = repo
        self.provider = provider
        self.auth = auth
    }

    func verify() async {
        guard let token = auth.token(), !token.isEmpty else {
            authState = .missingToken
            return
        }
        guard let provider else {
            authState = .missingToken
            return
        }
        do {
            let user = try await provider.verify()
            authState = .valid(user.login)
        } catch let error as ForgeError {
            if error == .unauthorized {
                authState = .invalid(error.errorDescription ?? "Invalid token.")
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load() async {
        guard let repo, let provider else {
            pullRequests = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            pullRequests = try await provider.listPullRequests(repo, state: filter)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ number: Int) async {
        guard let repo, let provider else { return }
        selectedPRNumber = number
        do {
            let detail = try await provider.pullRequest(repo, number: number)
            self.detail = detail
            self.files = (try? await provider.files(repo, number: number)) ?? []
            self.comments = (try? await provider.comments(repo, number: number)) ?? []
            self.checks = (try? await provider.checks(repo, ref: detail.headBranch)) ?? []
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func comment(_ body: String) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.addComment(repo, number: number, body: body)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ event: ReviewEvent, body: String) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.submitReview(repo, number: number, event: event, body: body)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(_ method: MergeMethod) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.merge(repo, number: number, method: method)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleForgeError(_ error: ForgeError) {
        errorMessage = error.errorDescription
        if error == .unauthorized {
            authState = .invalid(error.errorDescription ?? "Invalid token.")
        }
    }
}
