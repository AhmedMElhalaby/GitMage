import Testing
import Foundation
import AinkradAppKit
@testable import GitMageFeature

/// Records every payload the MCP tools forward, and answers with a fixed result
/// so the tests never touch a real repository.
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

// MARK: - tests

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GitMageMCPServerTests {
    /// Mirrors `GitOpTool.destructiveOperations` in the host, verbatim.
    static let hostDestructiveOperations: Set<String> = [
        "push", "deleteBranch", "deleteTag", "abortOperation",
        "rebase", "cherryPick", "revert",
    ]

    /// Every operation `GitOpTool.parametersSchema` advertises.
    static let hostOperations: [String] = [
        "status", "commit", "createBranch", "checkout", "deleteBranch", "push", "pull",
        "fetch", "stashPush", "stashPop", "stageAll", "unstageAll", "log", "rebase",
        "cherryPick", "revert", "reset", "createTag", "deleteTag", "tags",
        "removeWorktree", "opState", "continueOp", "abortOperation",
    ]

    private func makeServer(_ recorder: RecordingForwarder) -> (MCPAppServer, [String]) {
        GitMageMCPServer.make(appID: "gitmage") { await recorder.forward($0) }
    }

    @Test func everyToolRegistersSuccessfully() async {
        let (_, failures) = makeServer(RecordingForwarder())
        #expect(failures.isEmpty, "addTool rejected: \(failures)")
    }

    @Test func publishesEveryHostOperation() async {
        let (server, _) = makeServer(RecordingForwarder())
        let published = Set(GitMageMCPServer.tools.map(\.operation))
        for operation in Self.hostOperations {
            #expect(published.contains(operation), "missing operation \(operation)")
        }
        // Every published tool is actually listed over the wire.
        let listed = Set(await listedTools(server).compactMap { $0["name"] as? String })
        #expect(listed == Set(GitMageMCPServer.tools.map(\.name)))
    }

    @Test func destructiveHintsMatchTheHostSet() async {
        let (server, _) = makeServer(RecordingForwarder())
        let listed = await listedTools(server)
        for tool in GitMageMCPServer.tools {
            guard let entry = listed.first(where: { $0["name"] as? String == tool.name }) else {
                Issue.record("tool \(tool.name) was not listed"); continue
            }
            // The two injecting variants are destructive by construction; every
            // other tool follows the host's operation-token set exactly.
            let expected = tool.name == "reset_hard" || tool.name == "remove_worktree_force"
                ? true
                : Self.hostDestructiveOperations.contains(tool.operation)
            #expect(destructiveHint(entry) == expected, "wrong destructiveHint for \(tool.name)")
        }
    }

    @Test func splitVariantsExistAndAreDestructive() async {
        let (server, _) = makeServer(RecordingForwarder())
        let listed = await listedTools(server)
        for name in ["reset_hard", "remove_worktree_force"] {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else {
                Issue.record("missing \(name)"); continue
            }
            #expect(destructiveHint(entry))
        }
    }

    @Test func callForwardsOperationAndArguments() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "commit",
                                 arguments: ["repoPath": "/r", "args": ["message": "hello"]])
        #expect(outcome.isError == false)
        #expect(outcome.text == "ok")
        let payload = recorder.lastObject
        #expect(payload?["operation"] as? String == "commit")
        #expect(payload?["repoPath"] as? String == "/r")
        #expect((payload?["args"] as? [String: Any])?["message"] as? String == "hello")
    }

    @Test func resetRejectsHardMode() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "reset",
                                 arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": "hard"]])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty, "a rejected call must never reach the handler")
    }

    @Test func resetAllowsSafeModes() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "reset",
                                 arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": "soft"]])
        #expect(outcome.isError == false)
        #expect((recorder.lastObject?["args"] as? [String: Any])?["mode"] as? String == "soft")
    }

    @Test func resetHardInjectsHardMode() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(server, "reset_hard", arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1"]])
        #expect(recorder.lastObject?["operation"] as? String == "reset")
        #expect((recorder.lastObject?["args"] as? [String: Any])?["mode"] as? String == "hard")
    }

    @Test func removeWorktreeRejectsForce() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "remove_worktree",
                                 arguments: ["repoPath": "/r", "args": ["path": "/w", "force": true]])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty, "a rejected call must never reach the handler")
    }

    @Test func removeWorktreeForceInjectsForce() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(server, "remove_worktree_force",
                       arguments: ["repoPath": "/r", "args": ["path": "/w"]])
        #expect(recorder.lastObject?["operation"] as? String == "removeWorktree")
        #expect((recorder.lastObject?["args"] as? [String: Any])?["force"] as? Bool == true)
    }

    @Test func runtimeCachesOneServerPerHostAndEvictsIt() async {
        let host = FakeHostServices(context: RecordingContextRegistry())
        let first = GitMageRuntime.mcpServer(for: host)
        #expect(GitMageRuntime.mcpServer(for: host) === first)

        GitMageRuntime.teardown(instance: GitMageRuntime.instance(of: host), host: host)
        #expect(GitMageRuntime.mcpServer(for: host) !== first)
    }

    @Test func appPublishesTheRuntimeServer() async {
        let host = FakeHostServices(context: RecordingContextRegistry())
        #expect(GitMageApp.makeMCPServer(host: host) === GitMageRuntime.mcpServer(for: host))
    }

    @Test func missingRepoPathIsAnErrorNotAForwardedCall() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "status", arguments: [:])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty)
    }
}
