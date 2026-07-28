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

// MARK: - evasion cases
//
// File-scope (not nested in the suite) because `@Test(arguments:)` reads the
// table from outside the actor, and the suite is `@MainActor`.

/// One spelling of a dangerous argument. The value is built by a closure so the
/// table can hold heterogeneous JSON values and still be `Sendable`.
struct Evasion: Sendable, CustomStringConvertible {
    let label: String
    let value: @Sendable () -> Any
    init(_ label: String, _ value: @escaping @Sendable () -> Any) {
        self.label = label
        self.value = value
    }
    var description: String { label }
}

/// Casings, types and wrappings a caller could try in place of the literal
/// `mode: "hard"` that `reset`'s guard rejects.
let resetEvasions: [Evasion] = [
    Evasion("capitalised") { "Hard" },
    Evasion("upper-cased") { "HARD" },
    Evasion("leading space") { " hard" },
    Evasion("trailing space") { "hard " },
    Evasion("number") { 1 },
    Evasion("array wrapping the string") { ["hard"] },
    Evasion("object wrapping the string") { ["mode": "hard"] },
]

/// The same, for the literal `force: true` that `remove_worktree`'s guard
/// rejects. (`1` is covered separately — it bridges to `NSNumber` and IS caught.)
let forceEvasions: [Evasion] = [
    Evasion("string \"true\"") { "true" },
    Evasion("string \"TRUE\"") { "TRUE" },
    Evasion("string \"yes\"") { "yes" },
    Evasion("array wrapping true") { [true] },
    Evasion("object wrapping true") { ["force": true] },
]

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

    // MARK: - evasion of the ungated tools' guards
    //
    // The property under test is NOT "the call returned an error" — an error
    // string would still read as a pass if the dangerous argument leaked past
    // it. It is: **a hard reset / a forced worktree removal never happens
    // through the ungated tool**. So every case asserts on the payload actually
    // forwarded to `GitOpActionHandler`, resolved through the handler's OWN
    // coercion expression (`resolvedMode` / `resolvedForce` below).

    /// The exact expression `GitOpActionHandler.run` uses for `reset`'s mode
    /// (`ResetMode(rawValue: (args["mode"] as? String) ?? "mixed")`). Mirrored
    /// here so an evasion case is judged by what the SINK would do, not by what
    /// the guard happens to catch.
    private func resolvedMode(_ payload: [String: Any]?) -> ResetMode? {
        guard let payload else { return nil }   // nothing forwarded → nothing ran
        let args = payload["args"] as? [String: Any] ?? [:]
        return ResetMode(rawValue: (args["mode"] as? String) ?? "mixed")
    }

    /// The exact expression `GitOpActionHandler.run` uses for `removeWorktree`'s
    /// force flag: `(args["force"] as? Bool) ?? false`.
    private func resolvedForce(_ payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        let args = payload["args"] as? [String: Any] ?? [:]
        return (args["force"] as? Bool) ?? false
    }

    @Test(arguments: resetEvasions)
    func resetNeverPerformsAHardResetHoweverModeIsSpelled(evasion: Evasion) async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(server, "reset",
                       arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": evasion.value()]])
        #expect(resolvedMode(recorder.lastObject) != .hard,
                "reset reached a hard reset via \(evasion.label)")
    }

    @Test func resetIgnoresANestedOrDifferentlyCasedModeKey() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)

        // A nested `args.args.mode` — neither the guard nor the sink reads it.
        _ = await call(server, "reset",
                       arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "args": ["mode": "hard"]]])
        #expect(resolvedMode(recorder.lastObject) != .hard, "a nested args.mode reached the sink")

        // A `"Mode"` key: missed by the guard, and equally missed by the sink.
        _ = await call(server, "reset",
                       arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "Mode": "hard"]])
        #expect(resolvedMode(recorder.lastObject) != .hard, "a differently-cased Mode key reached the sink")
    }

    @Test(arguments: forceEvasions)
    func removeWorktreeNeverForcesHoweverForceIsSpelled(evasion: Evasion) async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(server, "remove_worktree",
                       arguments: ["repoPath": "/r", "args": ["path": "/w", "force": evasion.value()]])
        #expect(resolvedForce(recorder.lastObject) == false,
                "remove_worktree reached a forced removal via \(evasion.label)")
    }

    @Test func removeWorktreeRejectsNumericTrueAndIgnoresNearMissKeys() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)

        // `1` bridges to NSNumber, which `as? Bool` accepts — so BOTH the guard
        // and the sink read it as true. The guard must therefore reject it, and
        // nothing may be forwarded.
        let numeric = await call(server, "remove_worktree",
                                 arguments: ["repoPath": "/r", "args": ["path": "/w", "force": 1]])
        #expect(numeric.isError)
        #expect(recorder.payloads.isEmpty, "force: 1 was forwarded instead of rejected")

        _ = await call(server, "remove_worktree",
                       arguments: ["repoPath": "/r", "args": ["path": "/w", "args": ["force": true]]])
        #expect(resolvedForce(recorder.lastObject) == false, "a nested args.force reached the sink")

        _ = await call(server, "remove_worktree",
                       arguments: ["repoPath": "/r", "args": ["path": "/w", "Force": true]])
        #expect(resolvedForce(recorder.lastObject) == false, "a differently-cased Force key reached the sink")
    }

    /// Pins the coupling the `reset` guard depends on, **through the real
    /// sink**. The guard rejects only the LITERAL `mode: "hard"`; every spelling
    /// in `resetEvasions` is safe solely because `GitOpActionHandler` parses the
    /// mode with an exact, case-sensitive `ResetMode(rawValue:)` and refuses
    /// anything else before it reaches git.
    ///
    /// This drives the actual handler rather than a mirror of it, so making it
    /// tolerant (`rawValue: mode.lowercased()`, a trimming step, an alias table)
    /// fails HERE — which is the whole point: a mirrored expression in the test
    /// would keep passing while `"Hard"` became a live, ungated hard reset.
    ///
    /// Git-free: the `reset` branch validates `ref` and then `mode`, returning
    /// the mode error before it ever calls `GitRepositoryClient`.
    @Test func theResetSinkRejectsEveryNonExactSpellingOfHard() async {
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        for spelling in ["Hard", "HARD", " hard", "hard "] {
            let payload = #"{"operation":"reset","repoPath":"/nonexistent","args":{"ref":"HEAD~1","mode":"\#(spelling)"}}"#
            let result = await handler.run(payload)
            #expect(result.isError, "GitOpActionHandler now accepts mode \"\(spelling)\"")
            #expect(result.text.contains("must be soft, mixed, or hard"),
                    "GitOpActionHandler now coerces mode \"\(spelling)\" instead of refusing it — widen GitMageMCPServer's reset guard in lockstep, or the ungated reset tool becomes a live hard reset")
        }
        // The exact spelling is the one the guard already refuses, so it must
        // stay the ONLY spelling the sink accepts.
        #expect(ResetMode(rawValue: "hard") == .hard)
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
