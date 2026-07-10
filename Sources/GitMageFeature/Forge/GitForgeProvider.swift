import Foundation
import AinkradAppKit

/// Errors surfaced by a `GitForgeProvider` implementation, mapped from
/// transport failures and non-2xx HTTP responses.
enum ForgeError: Error, LocalizedError, Equatable {
    case unauthorized
    case forbidden(String)
    case notFound
    case server(Int)
    case decoding
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid or missing GitHub token."
        case .forbidden(let message): return message
        case .notFound: return "Not found."
        case .server(let code): return "GitHub server error (\(code))."
        case .decoding: return "Unexpected response from GitHub."
        case .transport(let message): return message
        }
    }
}

/// A forge (e.g. GitHub) pull-request backend. Implementations map their
/// wire format to the plain models in `ForgeModels.swift`.
protocol GitForgeProvider {
    func verify() async throws -> ForgeUser
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary]
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile]
    func comments(_ repo: RepoRef, number: Int) async throws -> [PRComment]
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun]
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws
}

/// Wraps the host's `PluginSecretStore` to read/write the GitHub token.
/// Never logs or persists the token outside the secret store.
struct GitForgeAuth {
    static let key = "github-token"

    private let secrets: PluginSecretStore

    init(secrets: PluginSecretStore) {
        self.secrets = secrets
    }

    func token() -> String? {
        secrets.secret(forKey: Self.key)
    }

    func setToken(_ value: String?) {
        let normalized = (value?.isEmpty ?? true) ? nil : value
        secrets.setSecret(normalized, forKey: Self.key)
    }

    func clear() {
        secrets.setSecret(nil, forKey: Self.key)
    }
}
