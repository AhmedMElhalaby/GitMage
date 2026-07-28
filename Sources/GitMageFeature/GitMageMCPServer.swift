import Foundation
import AinkradAppKit

/// Publishes Git Mage's git operations to the host assistant as MCP tools.
///
/// One tool per operation the host's old hard-coded `git_op` tool advertised.
/// Every tool forwards to the SAME `GitOpActionHandler` the `gitmage.git_op`
/// action used, with the tool name's operation token injected, so behaviour is
/// identical to the pre-MCP path — this is a new front door, not a new backend.
///
/// `destructive` mirrors `GitOpTool.destructiveOperations` verbatim, because it
/// is what the host's Full-auto guard gates on. The host also treated two cases
/// as irreversible *by argument* — `reset` with `mode: hard`, and
/// `removeWorktree` with `force: true` — which a static per-tool flag cannot
/// express. Those are split into a safe tool that REJECTS the dangerous
/// argument and a `destructive: true` twin that injects it itself. The
/// rejection is the load-bearing half: without it the dangerous behaviour would
/// still be reachable through the ungated tool.
@MainActor
enum GitMageMCPServer {
    /// Which handler a tool's payload is forwarded to.
    enum Route {
        /// `GitOpActionHandler` — local git.
        case git
        /// `PrOpActionHandler` — the GitHub forge provider.
        case pullRequest
    }

    /// One published tool.
    struct Tool {
        /// The MCP tool name (snake_case, MCP convention).
        let name: String
        /// The operation token forwarded to the tool's handler.
        let operation: String
        /// The handler the payload goes to. Both handlers take the identical
        /// `{operation, repoPath, args}` shape, so only the destination differs.
        var route: Route = .git
        let summary: String
        /// Surfaced as `destructiveHint`; the host gates irreversible calls on it.
        let destructive: Bool
        let readOnly: Bool
        /// Describes the tool's `args` object in its schema.
        let argsHint: String
        /// An `args` key this tool must refuse — the caller has to use the
        /// destructive twin instead. Refusing `("mode", .string("hard"))` means
        /// `mode: hard` never reaches git through the ungated tool.
        ///
        /// **This is an EXACT match, and that is safe only because it uses the
        /// same coercion as the sink.** `GitOpActionHandler.run` reads the two
        /// guarded arguments as `ResetMode(rawValue: (args["mode"] as? String)
        /// ?? "mixed")` and `(args["force"] as? Bool) ?? false`. `ResetMode` is
        /// a lower-case `String` raw-value enum with an exact `init(rawValue:)`,
        /// so `"Hard"`, `" hard"` and a non-string `mode` all fail at the SINK
        /// rather than slipping past this guard into git; `1` bridges to
        /// `NSNumber`, which `as? Bool` accepts at BOTH ends, so the guard
        /// catches it.
        ///
        /// If the handler is ever made more tolerant — `rawValue:
        /// mode.lowercased()`, a trimming step, an alias table, a string-to-bool
        /// coercion for `force` — this guard MUST be widened in lockstep, or the
        /// ungated tool becomes a live hard reset / forced removal with no
        /// approval gate. In `GitMageMCPServerTests`,
        /// `theResetSinkIsCaseSensitiveWhichIsWhatMakesTheGuardSufficient` fails
        /// first if that coupling breaks, and the
        /// `resetNeverPerformsAHardResetHoweverModeIsSpelled` /
        /// `removeWorktreeNeverForcesHoweverForceIsSpelled` tables cover the
        /// individual spellings.
        var rejects: (key: String, value: ArgumentValue)?
        /// An `args` key this tool sets itself, ignoring whatever was passed.
        var injects: (key: String, value: ArgumentValue)?

        init(_ name: String, _ operation: String, _ summary: String,
             route: Route = .git,
             destructive: Bool = false, readOnly: Bool = false, argsHint: String = "None.",
             rejects: (key: String, value: ArgumentValue)? = nil,
             injects: (key: String, value: ArgumentValue)? = nil) {
            self.name = name
            self.operation = operation
            self.route = route
            self.summary = summary
            self.destructive = destructive
            self.readOnly = readOnly
            self.argsHint = argsHint
            self.rejects = rejects
            self.injects = injects
        }
    }

    /// The argument shapes the reject/inject rules need.
    ///
    /// `.string`/`.bool` are EXACT matches, which is safe only because their
    /// sinks are exact too (see the long note on `Tool.rejects`).
    /// `.approvingReviewEvent` is the deliberate exception: its sink is
    /// case-insensitive and carries an alias, so an exact match would be a hole.
    enum ArgumentValue {
        case string(String)
        case bool(Bool)
        /// Any spelling of `event` that `PrOpActionHandler` would resolve to
        /// `ReviewEvent.approve`.
        case approvingReviewEvent

        /// Whether a value decoded from the call's arguments equals this one.
        func matches(_ any: Any) -> Bool {
            switch self {
            case .string(let s): return (any as? String) == s
            case .bool(let b):   return (any as? Bool) == b
            case .approvingReviewEvent:
                // Resolved through the SINK'S OWN function rather than a
                // mirrored comparison, because that sink is loose: it does
                // `raw.lowercased()` and aliases `"approved"`. An exact match
                // on `"approve"` would let "Approve", "APPROVE" and "approved"
                // through the ungated tool as live approvals. Calling the real
                // parser means any spelling added there is refused here in the
                // same commit — there is no lockstep left to forget.
                guard let raw = any as? String else { return false }
                return PrOpActionHandler.reviewEvent(raw) == .approve
            }
        }

        var foundation: Any {
            switch self {
            case .string(let s): return s
            case .bool(let b):   return b
            case .approvingReviewEvent: return ReviewEvent.approve.rawValue
            }
        }

        var described: String {
            switch self {
            case .string(let s): return "\"\(s)\""
            case .bool(let b):   return "\(b)"
            case .approvingReviewEvent: return "an approving review"
            }
        }
    }

    /// Everything published: the local-git tools plus the pull-request tools
    /// (`prTools`, in `GitMageMCPServer+PR.swift`).
    static var tools: [Tool] { gitTools + prTools }

    /// The local-git set. Operation tokens and destructive flags are copied from
    /// `GitOpTool` in the host (`parametersSchema` and `destructiveOperations`).
    static let gitTools: [Tool] = [
        Tool("status", "status", "Show the working-tree status of a repository.", readOnly: true),
        Tool("commit", "commit", "Commit the staged changes.", argsHint: "{\"message\": string} (required)"),
        Tool("create_branch", "createBranch", "Create a branch.", argsHint: "{\"name\": string} (required)"),
        Tool("checkout", "checkout", "Check out a branch.", argsHint: "{\"name\": string} (required)"),
        Tool("delete_branch", "deleteBranch", "Delete a branch.", destructive: true,
             argsHint: "{\"name\": string} (required)"),
        Tool("push", "push", "Push the current branch to its remote.", destructive: true),
        Tool("pull", "pull", "Pull the current branch from its remote."),
        Tool("fetch", "fetch", "Fetch from the remote."),
        Tool("stash_push", "stashPush", "Stash the working-tree changes."),
        Tool("stash_pop", "stashPop", "Pop the most recent stash."),
        Tool("stage_all", "stageAll", "Stage every change."),
        Tool("unstage_all", "unstageAll", "Unstage every staged change."),
        Tool("log", "log", "Read the commit log.", readOnly: true, argsHint: "{\"limit\": number} (default 20)"),
        Tool("rebase", "rebase", "Rebase the current branch onto a ref.", destructive: true,
             argsHint: "{\"onto\": string (required), \"autostash\": bool}"),
        Tool("cherry_pick", "cherryPick", "Cherry-pick a commit.", destructive: true,
             argsHint: "{\"sha\": string} (required)"),
        Tool("revert", "revert", "Revert a commit.", destructive: true, argsHint: "{\"sha\": string} (required)"),
        Tool("reset", "reset", "Reset to a ref with a non-destructive mode (soft or mixed). "
             + "Use reset_hard for a hard reset — it discards working-tree changes.",
             argsHint: "{\"ref\": string (required), \"mode\": \"soft\"|\"mixed\", \"autostash\": bool}",
             rejects: (key: "mode", value: .string("hard"))),
        Tool("reset_hard", "reset", "Hard-reset to a ref, DISCARDING all working-tree changes.",
             destructive: true,
             argsHint: "{\"ref\": string (required), \"autostash\": bool} — mode is always \"hard\".",
             injects: (key: "mode", value: .string("hard"))),
        Tool("create_tag", "createTag", "Create a tag.",
             argsHint: "{\"name\": string (required), \"message\": string, \"ref\": string}"),
        Tool("delete_tag", "deleteTag", "Delete a tag.", destructive: true,
             argsHint: "{\"name\": string} (required)"),
        Tool("tags", "tags", "List the repository's tags.", readOnly: true),
        Tool("remove_worktree", "removeWorktree", "Remove a clean worktree. "
             + "Use remove_worktree_force to remove one with uncommitted changes.",
             argsHint: "{\"path\": string} (required). \"force\" is refused here — "
             + "call remove_worktree_force to remove a worktree with uncommitted changes.",
             rejects: (key: "force", value: .bool(true))),
        Tool("remove_worktree_force", "removeWorktree",
             "Force-remove a worktree, DISCARDING any uncommitted changes in it.",
             destructive: true, argsHint: "{\"path\": string} (required) — force is always true.",
             injects: (key: "force", value: .bool(true))),
        Tool("op_state", "opState", "Report any in-progress merge/rebase/cherry-pick.", readOnly: true),
        Tool("continue_op", "continueOp", "Continue the in-progress operation."),
        Tool("abort_operation", "abortOperation", "Abort the in-progress operation.", destructive: true),
    ]

    /// Builds the server. Both closures receive the same
    /// `{operation, repoPath, args}` payload shape: `forward` is
    /// `GitOpActionHandler.run` (local git), `forwardPR` is
    /// `PrOpActionHandler.run` (the GitHub forge provider). A tool's `route`
    /// decides which one it reaches — nothing else differs between the paths.
    ///
    /// Returns the names of any tools `addTool` refused alongside the server: a
    /// dropped tool is a silently missing capability, so the caller must not be
    /// able to ignore it by accident.
    static func make(appID: String,
                     forward: @escaping @MainActor @Sendable (String) async -> AgentActionResult,
                     forwardPR: @escaping @MainActor @Sendable (String) async -> AgentActionResult)
        -> (server: MCPAppServer, failures: [String]) {
        let server = MCPAppServer(appID: appID)
        var failures: [String] = []
        for tool in tools {
            let sink = tool.route == .pullRequest ? forwardPR : forward
            let added = server.addTool(MCPToolSpec(
                name: tool.name,
                description: tool.summary,
                schemaJSON: schemaJSON(for: tool),
                destructive: tool.destructive,
                readOnly: tool.readOnly,
                handler: { arguments in await invoke(tool, arguments: arguments, forward: sink) }
            ))
            if !added { failures.append(tool.name) }
        }
        return (server, failures)
    }

    // MARK: - call handling

    private static func invoke(_ tool: Tool, arguments: String,
                               forward: @MainActor @Sendable (String) async -> AgentActionResult)
        async -> AgentActionResult {
        guard let data = arguments.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return AgentActionResult(text: "\(tool.name): malformed arguments", isError: true)
        }
        guard let repoPath = object["repoPath"] as? String, !repoPath.isEmpty else {
            return AgentActionResult(text: "\(tool.name) requires a \"repoPath\".", isError: true)
        }
        var args = object["args"] as? [String: Any] ?? [:]

        // The gate: a caller must not reach the irreversible behaviour through
        // the tool the host does not treat as destructive.
        if let rule = tool.rejects, let passed = args[rule.key], rule.value.matches(passed) {
            return AgentActionResult(
                text: "\(tool.name) refuses args.\(rule.key) = \(rule.value.described) — "
                    + "it is irreversible and needs approval. Use the dedicated tool instead.",
                isError: true)
        }
        if let rule = tool.injects { args[rule.key] = rule.value.foundation }

        var payload: [String: Any] = ["operation": tool.operation, "repoPath": repoPath]
        if !args.isEmpty { payload["args"] = args }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return AgentActionResult(text: "\(tool.name): could not encode the request", isError: true)
        }
        return await forward(String(decoding: payloadData, as: UTF8.self))
    }

    // MARK: - schema

    /// Every tool takes the same shape as the host's old `git_op` minus
    /// `operation`, which the tool name now carries.
    private static func schemaJSON(for tool: Tool) -> String {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "repoPath": ["type": "string", "description": "Absolute path to the git repository."],
                "args": ["type": "object", "description": "Operation arguments. \(tool.argsHint)"],
            ],
            "required": ["repoPath"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: schema) else {
            return #"{"type":"object"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
