import Testing
import Foundation
import AinkradAppKit
@testable import GitMageFeature

// MARK: - doubles

/// Records the payloads the PR tools forward, so a routing test can prove a
/// call went down the PR path and NOT the git path.
@MainActor
private final class RecordingForwarder {
    private(set) var payloads: [String] = []
    func forward(_ json: String) async -> AgentActionResult {
        payloads.append(json)
        return AgentActionResult(text: "ok", isError: false)
    }
    var lastObject: [String: Any]? {
        guard let json = payloads.last, let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// A `GitForgeProvider` that answers from memory and records every call.
/// Nothing here touches the network — the handler is built with this instance
/// injected in place of `GitHubProvider`.
private final class StubForgeProvider: GitForgeProvider {
    var summaries: [PullRequestSummary] = []
    var detail: PullRequestDetail?
    var checkRuns: [CheckRun] = []
    var createdNumber = 42
    var thrownError: ForgeError?

    var listCalls: [PRState] = []
    var pullRequestCalls: [Int] = []
    var filesCalls: [Int] = []
    var commitsCalls: [Int] = []
    var commentsCalls: [Int] = []
    var checksCalls: [String] = []
    var addCommentCalls: [(number: Int, body: String)] = []
    var submitReviewCalls: [(number: Int, event: ReviewEvent, body: String)] = []
    var mergeCalls: [(number: Int, method: MergeMethod)] = []
    var createCalls: [(title: String, body: String, head: String, base: String, draft: Bool)] = []
    var setStateCalls: [(number: Int, state: PRState)] = []

    private func failIfNeeded() throws { if let thrownError { throw thrownError } }

    func verify() async throws -> ForgeUser { ForgeUser(login: "alice") }
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] {
        listCalls.append(state); try failIfNeeded(); return summaries
    }
    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws -> ForgePage<PullRequestSummary> {
        ForgePage(items: summaries, totalCount: summaries.count)
    }
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail {
        pullRequestCalls.append(number)
        try failIfNeeded()
        guard let detail else { throw ForgeError.notFound }
        return detail
    }
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] { filesCalls.append(number); return [] }
    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit] { commitsCalls.append(number); return [] }
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] { commentsCalls.append(number); return [] }
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] { checksCalls.append(ref); return checkRuns }
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {
        addCommentCalls.append((number, body)); try failIfNeeded()
    }
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {
        submitReviewCalls.append((number, event, body)); try failIfNeeded()
    }
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {
        mergeCalls.append((number, method)); try failIfNeeded()
    }
    func createPullRequest(_ repo: RepoRef, title: String, body: String, head: String, base: String, draft: Bool) async throws -> Int {
        createCalls.append((title, body, head, base, draft)); try failIfNeeded(); return createdNumber
    }
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws {
        setStateCalls.append((number, state)); try failIfNeeded()
    }

    func listIssues(_ repo: RepoRef, state: IssueState) async throws -> [IssueSummary] { [] }
    func searchIssues(_ repo: RepoRef, state: IssueState, query: String, labels: [String], page: Int) async throws -> ForgePage<IssueSummary> {
        ForgePage(items: [], totalCount: 0)
    }
    func issue(_ repo: RepoRef, number: Int) async throws -> IssueDetail { throw ForgeError.notFound }
    func issueComments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] { [] }
    func repoLabels(_ repo: RepoRef) async throws -> [IssueLabel] { [] }
    func assignableUsers(_ repo: RepoRef) async throws -> [ForgeUser] { [] }
    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String], assignees: [String]) async throws -> Int { 0 }
    func addIssueComment(_ repo: RepoRef, number: Int, body: String) async throws {}
    func setIssueState(_ repo: RepoRef, number: Int, state: IssueState) async throws {}
    func setLabels(_ repo: RepoRef, number: Int, labels: [String]) async throws {}
    func setAssignees(_ repo: RepoRef, number: Int, assignees: [String]) async throws {}
}

// MARK: - helpers

@MainActor
private func listedTools(_ server: MCPAppServer) async -> [[String: Any]] {
    let reply = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    guard let data = reply.data(using: .utf8),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let result = root["result"] as? [String: Any],
          let tools = result["tools"] as? [[String: Any]] else { return [] }
    return tools
}

@MainActor
private func call(_ server: MCPAppServer, _ name: String,
                  arguments: [String: Any]) async -> (text: String, isError: Bool) {
    let params: [String: Any] = ["name": name, "arguments": arguments]
    let request: [String: Any] = ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": params]
    let data = try! JSONSerialization.data(withJSONObject: request)
    let reply = await server.handle(String(decoding: data, as: UTF8.self))
    guard let replyData = reply.data(using: .utf8),
          let root = (try? JSONSerialization.jsonObject(with: replyData)) as? [String: Any],
          let result = root["result"] as? [String: Any],
          let content = result["content"] as? [[String: Any]] else {
        return ("<no result>", true)
    }
    return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
}

private func destructiveHint(_ tool: [String: Any]) -> Bool {
    (tool["annotations"] as? [String: Any])?["destructiveHint"] as? Bool ?? false
}

private func readOnlyHint(_ tool: [String: Any]) -> Bool {
    (tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool ?? false
}

// MARK: - tests

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GitMagePROpTests {
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    private func makeDetail(number: Int = 7) -> PullRequestDetail {
        PullRequestDetail(number: number, title: "Fix", body: "body", state: "open", isDraft: false,
                          author: "alice", createdAt: "2026-07-01T00:00:00Z", mergeable: true,
                          mergeableState: "clean", additions: 1, deletions: 0,
                          headBranch: "feat", baseBranch: "main")
    }

    /// Builds the real server with BOTH forwarders, where the PR one is the real
    /// `PrOpActionHandler` wired to an in-memory provider and a fixed repo — so
    /// a call exercises tool → handler → provider without any git or network.
    private func makeServer(_ provider: StubForgeProvider,
                            gitRecorder: RecordingForwarder = RecordingForwarder())
        -> (MCPAppServer, [String]) {
        let handler = PrOpActionHandler(
            resolveRepo: { _ in self.repo },
            makeProvider: { provider }
        )
        return GitMageMCPServer.make(
            appID: "gitmage",
            forward: { await gitRecorder.forward($0) },
            forwardPR: { await handler.run($0) }
        )
    }

    // MARK: publication

    @Test func publishesEveryPRToolAndNothingIsRejected() async {
        let (server, failures) = makeServer(StubForgeProvider())
        #expect(failures.isEmpty, "addTool rejected: \(failures)")

        let listed = Set(await listedTools(server).compactMap { $0["name"] as? String })
        let expected: Set<String> = ["pr_list", "pr_view", "pr_checks", "pr_create",
                                     "pr_comment", "pr_review", "pr_merge", "pr_close"]
        #expect(expected.isSubset(of: listed), "missing: \(expected.subtracting(listed))")
        // The git tools are still published alongside them.
        #expect(listed.contains("status"))
        #expect(listed == Set(GitMageMCPServer.tools.map(\.name)))
    }

    @Test func destructiveHintsMatchTheClassification() async {
        let (server, _) = makeServer(StubForgeProvider())
        let listed = await listedTools(server)
        // Only merging and closing destroy or foreclose state that cannot be
        // restored through the API. Creating a PR, commenting and reviewing are
        // additive and remediable, so they stay ungated.
        let expected: [String: Bool] = [
            "pr_list": false, "pr_view": false, "pr_checks": false, "pr_create": false,
            "pr_comment": false, "pr_review": false, "pr_merge": true, "pr_close": true,
        ]
        for (name, flag) in expected {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else {
                Issue.record("tool \(name) was not listed"); continue
            }
            #expect(destructiveHint(entry) == flag, "wrong destructiveHint for \(name)")
        }
        for name in ["pr_list", "pr_view", "pr_checks"] {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else { continue }
            #expect(readOnlyHint(entry), "\(name) should be readOnly")
        }
    }

    // MARK: routing

    @Test func aPRCallGoesDownThePRPathAndNeverTheGitPath() async {
        let provider = StubForgeProvider()
        let gitRecorder = RecordingForwarder()
        let (server, _) = makeServer(provider, gitRecorder: gitRecorder)

        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])

        #expect(outcome.isError == false)
        #expect(provider.listCalls == [.open], "pr_list did not reach the forge provider")
        #expect(gitRecorder.payloads.isEmpty, "a PR call reached the git handler")
    }

    @Test func aGitCallStillGoesDownTheGitPath() async {
        let provider = StubForgeProvider()
        let gitRecorder = RecordingForwarder()
        let (server, _) = makeServer(provider, gitRecorder: gitRecorder)

        _ = await call(server, "status", arguments: ["repoPath": "/r"])

        #expect(gitRecorder.lastObject?["operation"] as? String == "status")
        #expect(provider.listCalls.isEmpty)
    }

    @Test func missingRepoPathIsAnErrorNotAForwardedCall() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_list", arguments: [:])
        #expect(outcome.isError)
        #expect(provider.listCalls.isEmpty)
    }

    // MARK: argument forwarding, tool by tool

    @Test func prListForwardsTheStateFilter() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_list", arguments: ["repoPath": "/r", "args": ["state": "closed"]])
        #expect(provider.listCalls == [.closed])
    }

    @Test func prViewForwardsTheNumberToEveryDetailCall() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_view", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(outcome.isError == false)
        #expect(provider.pullRequestCalls == [7])
        #expect(provider.filesCalls == [7])
        #expect(provider.commitsCalls == [7])
        #expect(provider.commentsCalls == [7])
    }

    @Test func prChecksResolvesTheHeadBranchThenAsksForCheckRuns() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_checks", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(provider.pullRequestCalls == [7])
        #expect(provider.checksCalls == ["feat"], "pr_checks must query the PR's head branch")
    }

    @Test func prCreateForwardsTitleBodyHeadBaseAndDraft() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_create", arguments: [
            "repoPath": "/r",
            "args": ["title": "T", "body": "B", "head": "feat", "base": "main", "draft": true],
        ])
        #expect(outcome.isError == false)
        #expect(provider.createCalls.count == 1)
        #expect(provider.createCalls.first?.title == "T")
        #expect(provider.createCalls.first?.body == "B")
        #expect(provider.createCalls.first?.head == "feat")
        #expect(provider.createCalls.first?.base == "main")
        #expect(provider.createCalls.first?.draft == true)
    }

    @Test func prCreateRequiresTitleHeadAndBase() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_create", arguments: ["repoPath": "/r", "args": ["title": "T"]])
        #expect(outcome.isError)
        #expect(provider.createCalls.isEmpty)
    }

    @Test func prCommentForwardsNumberAndBody() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_comment",
                       arguments: ["repoPath": "/r", "args": ["number": 7, "body": "nice"]])
        #expect(provider.addCommentCalls.count == 1)
        #expect(provider.addCommentCalls.first?.number == 7)
        #expect(provider.addCommentCalls.first?.body == "nice")
    }

    @Test func prReviewForwardsTheEventAndBody() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_review",
                       arguments: ["repoPath": "/r", "args": ["number": 7, "event": "approve", "body": "LGTM"]])
        #expect(provider.submitReviewCalls.count == 1)
        #expect(provider.submitReviewCalls.first?.event == .approve)
        #expect(provider.submitReviewCalls.first?.body == "LGTM")
    }

    @Test func prReviewRejectsAnUnknownEvent() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_review",
                                 arguments: ["repoPath": "/r", "args": ["number": 7, "event": "yolo"]])
        #expect(outcome.isError)
        #expect(provider.submitReviewCalls.isEmpty)
    }

    @Test func prMergeForwardsTheMergeMethodAndDefaultsToMerge() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_merge",
                       arguments: ["repoPath": "/r", "args": ["number": 7, "method": "squash"]])
        #expect(provider.mergeCalls.first?.number == 7)
        #expect(provider.mergeCalls.first?.method == .squash)

        _ = await call(server, "pr_merge", arguments: ["repoPath": "/r", "args": ["number": 8]])
        #expect(provider.mergeCalls.last?.method == .merge)
    }

    @Test func prCloseSetsTheClosedState() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_close", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(provider.setStateCalls.count == 1)
        #expect(provider.setStateCalls.first?.number == 7)
        #expect(provider.setStateCalls.first?.state == .closed)
    }

    // MARK: preconditions — a PR tool must fail loudly, never silently no-op

    @Test func aMissingTokenIsAClearErrorAndNeverReachesTheProvider() async {
        let handler = PrOpActionHandler(resolveRepo: { _ in self.repo }, makeProvider: { nil })
        let (server, _) = GitMageMCPServer.make(appID: "gitmage",
                                                forward: { _ in AgentActionResult(text: "", isError: false) },
                                                forwardPR: { await handler.run($0) })
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(outcome.text.lowercased().contains("token"))
    }

    @Test func anUnrecognizedRemoteIsAClearError() async {
        let provider = StubForgeProvider()
        let handler = PrOpActionHandler(resolveRepo: { _ in nil }, makeProvider: { provider })
        let (server, _) = GitMageMCPServer.make(appID: "gitmage",
                                                forward: { _ in AgentActionResult(text: "", isError: false) },
                                                forwardPR: { await handler.run($0) })
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(provider.listCalls.isEmpty)
    }

    @Test func aForgeErrorSurfacesAsAToolError() async {
        let provider = StubForgeProvider()
        provider.thrownError = .unauthorized
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(outcome.text.contains("token"))
    }
}
