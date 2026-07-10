import Foundation
import AinkradAppKit

final class GitHubProvider: GitForgeProvider {
    private let token: String
    private let session: URLSession
    private let base = URL(string: "https://api.github.com")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func verify() async throws -> ForgeUser {
        try await get("/user", as: GHUser.self).toModel()
    }
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls?state=\(state.rawValue)&per_page=50", as: [GHPull].self).map { $0.toSummary() }
    }
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)", as: GHPull.self).toDetail()
    }
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/files?per_page=50", as: [GHFile].self).map { $0.toModel() }
    }
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        try await get("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments?per_page=50", as: [GHComment].self).map { $0.toModel() }
    }
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] {
        try await get("/repos/\(repo.owner)/\(repo.name)/commits/\(ref)/check-runs", as: GHCheckRunsEnvelope.self).checkRuns.map { $0.toModel() }
    }
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {
        try await send("POST", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments", json: ["body": body])
    }
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {
        try await send("POST", "/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/reviews", json: ["event": event.rawValue, "body": body])
    }
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {
        try await send("PUT", "/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/merge", json: ["merge_method": method.rawValue])
    }

    // MARK: - Transport
    private func makeRequest(_ method: String, _ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }
    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let (data, resp) = try await run(makeRequest("GET", path))
        try Self.check(resp, data)
        do { return try decoder().decode(T.self, from: data) } catch { throw ForgeError.decoding }
    }
    private func send(_ method: String, _ path: String, json: [String: Any]) async throws {
        var req = makeRequest(method, path)
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await run(req)
        try Self.check(resp, data)
    }
    private func run(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) }
        catch { throw ForgeError.transport(error.localizedDescription) }
    }
    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw ForgeError.decoding }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ForgeError.unauthorized
        case 403: throw ForgeError.forbidden(message(data) ?? "Forbidden (check token scope or rate limit).")
        case 404: throw ForgeError.notFound
        default: throw ForgeError.server(http.statusCode)
        }
    }
    private static func message(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
    }
}
